import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Observation

/// The browser: the cards or notes matching a search in Anki's search syntax,
/// in the chosen sort order.
///
/// A search asks the core only for the matching row ids, in order, which
/// stays fast with a very large collection. Each card's row is fetched from
/// the core when it is needed (`loadRow(_:)`, called as the row appears),
/// together with the rest of its page of rows, and kept until the next search
/// or change makes it stale.
///
/// The learner can select cards (`selection`) and act on all of them at once
/// (`perform(_:)`, in CardBrowserModel+BulkActions.swift), and reach common
/// searches through quick filters (CardBrowserModel+QuickFilters.swift).
@MainActor
@Observable
public final class CardBrowserModel {
    public enum State: Equatable {
        case loading
        case loaded
        /// The search could not be understood; `message` is the core's
        /// explanation.
        case invalidSearch(message: String)
        case failed(message: String)
    }

    public enum Mode: Hashable, Sendable {
        case cards
        case notes

        var defaultColumns: [String] {
            switch self {
            case .cards: ["noteFld", "template", "cardDue", "deck"]
            case .notes: ["noteFld", "note", "template", "noteTags"]
            }
        }
        var columnsKey: String { self == .cards ? "activeCols" : "activeNoteCols" }
        var sortColumnKey: String { self == .cards ? "sortType" : "noteSortType" }
        var sortReverseKey: String { self == .cards ? "sortBackwards" : "browserNoteSortBackwards" }
    }

    public private(set) var state: State = .loading
    public private(set) var mode: Mode = .cards
    @ObservationIgnored private var hasLoadedMode = false
    @ObservationIgnored private var sorts: [Mode: CardSort] = [:]

    private var columnSelections: [Mode: [String]] = [:]
    public private(set) var availableColumns: [BrowserColumn] = []
    public var visibleColumnIDs: [String] { columnSelections[mode] ?? mode.defaultColumns }
    public var visibleColumns: [BrowserColumn] {
        visibleColumnIDs.compactMap { id in availableColumns.first { $0.id == id } }
    }

    /// The search in Anki's search syntax. Empty finds every card.
    public var searchText = ""
    var filterSelection: (query: String, filters: [QuickFilter], builtQuery: String)?

    /// The order of the results. Change it with `setSort(_:)`.
    public private(set) var sort: CardSort = .default

    /// The columns the current row mode can be sorted by, named in the core's language.
    /// Empty until the first search.
    public private(set) var sortColumns: [SortColumn] = []

    /// The search that found `rowIDs`, which may differ from `searchText`
    /// while the learner edits it.
    public private(set) var searchedText = ""

    /// The ids of the cards or notes matching the last search, in sort order.
    public private(set) var rowIDs: [Int64] = []

    /// Card IDs are available while Browse shows cards.
    public var cardIDs: [Int64] { mode == .cards ? rowIDs : [] }

    @ObservationIgnored private var rowIndices: [Int64: Int] = [:]

    /// Selected row IDs. Every search keeps only the selected rows it still lists.
    public var selection: Set<Int64> = []

    /// The decks and tags the quick filters and the Move action offer. Empty
    /// until `loadChoices()`.
    public internal(set) var choices = BrowserChoices()

    /// The last bulk action, which `undoLastAction()` can undo; nil once it
    /// is undone or can no longer be.
    public internal(set) var completedAction: CompletedAction?
    private(set) var availableUndo: (name: String, step: UInt32)?

    /// Why the last bulk action or undo failed, in the core's words.
    public var failure: String?
    public internal(set) var isPerformingAction = false

    public internal(set) var savedSearches: [SavedBrowserSearch] = []
    public internal(set) var flagNames: [CardRow.Flag: String] = [:]
    @ObservationIgnored var updatingSavedSearches = false

    @ObservationIgnored private var searchCount = 0
    @ObservationIgnored private var finishedSearch = 0
    @ObservationIgnored private var submittedSearch: String?

    /// The rows fetched so far, by card id.
    private var rows: [Int64: CachedRow] = [:]

    /// Increases whenever the shown rows may be out of date, so rows already
    /// fetched are fetched again when next needed.
    public private(set) var generation = 0

    /// The pages of rows being fetched, so a page is fetched once even when
    /// many of its rows appear at the same time.
    @ObservationIgnored private var pagesLoading: Set<PageKey> = []

    @ObservationIgnored let store: CollectionStore

    /// Changes after which the matching cards, their order or their rows may
    /// differ.
    private static let relevantChanges: CollectionChange = [
        .card, .note, .deck, .tag, .notetype, .browserTable, .noteText,
    ]

    /// How many rows are fetched together: about a few screens' worth, so
    /// scrolling rarely waits, while a search over a very large collection
    /// still fetches only what is shown.
    public static let pageSize = 50

    public init(store: CollectionStore) {
        self.store = store
    }

    /// Runs the current search in the current sort order.
    public func search() async {
        submittedSearch = searchText
        await refreshResults()
    }

    /// Refreshes the displayed query without submitting any unfinished text.
    func refreshResults() async {
        let text = submittedSearch ?? searchText
        submittedSearch = text
        await search(text: text)
    }

    private func search(text: String) async {
        // Searches can overlap (the learner submits while a change triggers
        // one); only the latest may update what is shown.
        searchCount += 1
        let thisSearch = searchCount
        do {
            if !hasLoadedMode {
                let notes = try await store.core.getConfigBool(.with { $0.key = .browserTableShowNotesMode }).val
                guard thisSearch == searchCount else { return }
                mode = notes ? .notes : .cards
                hasLoadedMode = true
            }
            let mode = mode
            let available = try await store.core.allBrowserColumns().columns
            let known = Set(available.map(\.key))
            let availableSort = available.filter { column in
                let sorting = mode == .cards ? column.sortingCards : column.sortingNotes
                return sorting != .none
            }
            let order: CardSort
            if let remembered = sorts[mode] {
                order = remembered
            } else {
                let key = try await readConfig(String.self, key: mode.sortColumnKey)
                let reverse = try await readConfig(Bool.self, key: mode.sortReverseKey) ?? false
                order = key.flatMap { key in
                    availableSort.contains { $0.key == key } ? CardSort(column: key, reverse: reverse) : nil
                } ?? .default
            }
            let columns: [String]
            if let remembered = columnSelections[mode] {
                columns = remembered
            } else {
                let saved = try await readConfig([String].self, key: mode.columnsKey) ?? []
                let valid = Self.validColumns(saved, known: known)
                columns = valid.isEmpty ? mode.defaultColumns : valid
            }
            guard thisSearch == searchCount else { return }
            // Active columns are transient core state and need to be restored after a reopen.
            try await store.core.setActiveBrowserColumns(.with { $0.vals = columns })
            let request = Anki_Search_SearchRequest.with {
                $0.search = text
                $0.order = order.order
            }
            let found = try await (mode == .cards ? store.core.searchCards(request) : store.core.searchNotes(request))
            let undo = try await store.core.getUndoStatus()
            guard thisSearch == searchCount else { return }
            availableUndo = undo.undo.isEmpty ? nil : (undo.undo, undo.lastStep)
            sorts[mode] = order
            sort = order
            columnSelections[mode] = columns
            availableColumns = available.map { column in
                BrowserColumn(id: column.key, label: mode == .cards ? column.cardsModeLabel : column.notesModeLabel)
            }
            sortColumns = availableSort.map { column in
                let sorting = mode == .cards ? column.sortingCards : column.sortingNotes
                let label = mode == .cards ? column.cardsModeLabel : column.notesModeLabel
                return SortColumn(id: column.key, label: label, startsDescending: sorting == .descending)
            }
            rowIDs = found.ids
            rowIndices = Dictionary(uniqueKeysWithValues: found.ids.enumerated().map { ($1, $0) })
            if !selection.isEmpty {
                selection.formIntersection(found.ids)
            }
            searchedText = text
            finishedSearch = thisSearch
            rows.removeAll(keepingCapacity: true)
            generation += 1
            state = .loaded
        } catch where error.kind == .searchError {
            guard thisSearch == searchCount else { return }
            rowIDs = []
            rowIndices = [:]
            rows.removeAll()
            selection = []
            searchedText = text
            finishedSearch = thisSearch
            availableUndo = nil
            state = .invalidSearch(message: error.message)
        } catch {
            guard thisSearch == searchCount else { return }
            availableUndo = nil
            state = .failed(message: error.message)
        }
    }

    /// Switches between one row per card and one row per note.
    public func setMode(_ newMode: Mode) async {
        guard newMode != mode else { return }
        searchCount += 1
        let change = searchCount
        hasLoadedMode = true
        mode = newMode
        sort = sorts[newMode] ?? .default
        availableColumns = []
        sortColumns = []
        state = .loading
        rowIDs = []
        rowIndices = [:]
        rows.removeAll()
        selection = []
        generation += 1

        do {
            _ = try await store.core.setConfigBool(.with {
                $0.key = .browserTableShowNotesMode
                $0.value = newMode == .notes
            })
        } catch {
            guard change == searchCount else { return }
            state = .failed(message: error.message)
            return
        }
        guard change == searchCount else { return }
        await refreshResults()
    }

    /// Sets the displayed columns, in the learner's chosen order.
    public func setColumns(_ columnIDs: [String]) async {
        let columns = Self.validColumns(columnIDs, known: Set(availableColumns.map(\.id)))
        guard !columns.isEmpty, columns != visibleColumnIDs else { return }
        let mode = mode
        do {
            try await writeConfig(columns, key: mode.columnsKey)
            columnSelections[mode] = columns
            if self.mode == mode { await refreshResults() }
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Sorts rows differently and searches again.
    public func setSort(_ newSort: CardSort) async {
        let mode = mode
        sort = newSort
        sorts[mode] = newSort
        do {
            try await writeConfig(newSort.column, key: mode.sortColumnKey)
            if sorts[mode] == newSort {
                try await writeConfig(newSort.reverse, key: mode.sortReverseKey)
            }
        } catch {
            failure = error.localizedDescription
        }
        if self.mode == mode { await refreshResults() }
    }

    private static func validColumns(_ requested: [String], known: Set<String>) -> [String] {
        var remaining = known
        return requested.filter { remaining.remove($0) != nil }
    }

    func readConfig<Value: Decodable>(_ type: Value.Type, key: String) async throws(CoreError) -> Value? {
        do {
            let json = try await store.core.getConfigJson(.with { $0.val = key }).json
            return try? JSONDecoder().decode(type, from: json)
        } catch where error.kind == .notFoundError {
            return nil
        }
    }

    func writeConfig(_ value: some Encodable, key: String) async throws {
        let json = try JSONEncoder().encode(value)
        _ = try await store.core.setConfigJson(.with {
            $0.key = key
            $0.valueJson = json
        })
    }

    /// Sorts the cards by another column, in that column's natural first
    /// order, and searches again.
    public func sortBy(_ column: SortColumn) async {
        await setSort(CardSort(column: column.id, reverse: column.startsDescending))
    }

    /// The row of a card, if it has been fetched.
    public func row(for cardID: Int64) -> CardRow? {
        rows[cardID]?.row
    }

    /// Fetches a card's row from the core unless an up-to-date one is kept,
    /// with the rest of its page of rows (`pageSize` rows of `cardIDs`), so
    /// scrolling fetches rows a page at a time.
    public func loadRow(_ cardID: Int64) async {
        guard finishedSearch == searchCount else { return }
        if let cached = rows[cardID], cached.generation == generation { return }
        guard let index = rowIndices[cardID] else { return }
        let page = index / Self.pageSize
        let key = PageKey(page: page, generation: generation)
        guard !pagesLoading.contains(key) else { return }
        pagesLoading.insert(key)
        defer { pagesLoading.remove(key) }
        let start = page * Self.pageSize
        let ids = rowIDs[start ..< min(start + Self.pageSize, rowIDs.count)]
            .filter { rows[$0]?.generation != generation }
        await loadRows(ids)
    }

    /// Fetches rows from the core and keeps them all at once, so the list
    /// redraws once per page rather than once per row.
    private func loadRows(_ ids: [Int64]) async {
        let generation = generation
        let search = searchCount
        let columns = visibleColumnIDs
        var fetched: [(Int64, CachedRow?)] = []
        for id in ids {
            guard generation == self.generation, search == searchCount else { return }
            do {
                let row = try await store.core.browserRowForId(.with { $0.val = id })
                fetched.append((id, CachedRow(row: CardRow(id: id, row, columnIDs: columns), generation: generation)))
            } catch {
                // A card deleted since the search: the next search drops it.
                fetched.append((id, nil))
            }
        }
        guard generation == self.generation, search == searchCount else { return }
        // No suspension point in between, so the list redraws once.
        for (id, row) in fetched {
            rows[id] = row
        }
    }

    /// Selects every listed card.
    public func selectAll() {
        selection = Set(rowIDs)
    }

    /// Selects no card.
    public func clearSelection() {
        selection = []
    }

    /// Shows the cards matching the search, then keeps the list current
    /// whenever the collection changes in a way that could alter it, until the
    /// calling task is cancelled. The browse screen runs this in its `.task`.
    public func run() async {
        let changes = store.changes()
        await refreshResults()
        await loadChoices()
        await loadFlagNames()
        for await change in changes where !change.isDisjoint(with: Self.relevantChanges) {
            if change == .everything {
                hasLoadedMode = false
                sorts.removeAll()
                columnSelections.removeAll()
                selection.removeAll()
                completedAction = nil
                await loadFlagNames()
            }
            await refreshResults()
            if !change.isDisjoint(with: [.deck, .tag, .note, .notetype]) {
                await loadChoices()
            }
        }
    }

    private struct CachedRow {
        let row: CardRow
        let generation: Int
    }

    private struct PageKey: Hashable {
        let page: Int
        let generation: Int
    }
}
