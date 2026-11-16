import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Observation

/// The card browser: the cards matching a search in Anki's search syntax,
/// in the chosen sort order.
///
/// A search asks the core only for the matching card ids, in order, which
/// stays fast with a very large collection. Each card's row is fetched from
/// the core when it is needed (`loadRow(_:)`, called as the row appears) and
/// kept until the next search or change makes it stale.
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

    public private(set) var state: State = .loading

    /// The search in Anki's search syntax. Empty finds every card.
    public var searchText = ""

    /// The order of the cards. Change it with `setSort(_:)`.
    public private(set) var sort: CardSort = .default

    /// The columns the cards can be sorted by, named in the core's language.
    /// Empty until the first search.
    public private(set) var sortColumns: [SortColumn] = []

    /// The search that found `cardIDs`, which may differ from `searchText`
    /// while the learner edits it.
    public private(set) var searchedText = ""

    /// The ids of the cards matching the last search, in sort order.
    public private(set) var cardIDs: [Int64] = []

    @ObservationIgnored private var searchCount = 0

    /// The rows fetched so far, by card id.
    private var rows: [Int64: CachedRow] = [:]

    /// Increases whenever the shown rows may be out of date, so rows already
    /// fetched are fetched again when next needed.
    public private(set) var generation = 0

    @ObservationIgnored private let store: CollectionStore

    /// Changes after which the matching cards, their order or their rows may
    /// differ.
    private static let relevantChanges: CollectionChange = [
        .card, .note, .deck, .tag, .notetype, .browserTable, .noteText,
    ]

    /// The columns the browser asks the core for, in the order of `CardRow`'s
    /// cells.
    static let columns = ["question", "deck", "cardDue"]

    public init(store: CollectionStore) {
        self.store = store
    }

    /// Runs the current search in the current sort order.
    public func search() async {
        // Searches can overlap (the learner submits while a change triggers
        // one); only the latest may update what is shown.
        searchCount += 1
        let thisSearch = searchCount
        let text = searchText
        let order = sort.order
        do {
            // The core keeps the columns per open collection, so set them
            // every time: the collection may have been reopened since.
            try await store.core.setActiveBrowserColumns(.with { $0.vals = Self.columns })
            if sortColumns.isEmpty {
                sortColumns = try await store.core.allBrowserColumns().columns
                    .filter { $0.sortingCards != .none }
                    .map { SortColumn(id: $0.key, label: $0.cardsModeLabel, startsDescending: $0.sortingCards == .descending) }
            }
            let found = try await store.core.searchCards(.with {
                $0.search = text
                $0.order = order
            })
            guard thisSearch == searchCount else { return }
            cardIDs = found.ids
            searchedText = text
            generation += 1
            state = .loaded
        } catch where error.kind == .searchError {
            guard thisSearch == searchCount else { return }
            cardIDs = []
            searchedText = text
            state = .invalidSearch(message: error.message)
        } catch {
            guard thisSearch == searchCount else { return }
            state = .failed(message: error.message)
        }
    }

    /// Sorts the cards differently and searches again.
    public func setSort(_ newSort: CardSort) async {
        sort = newSort
        await search()
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

    /// Fetches a card's row from the core unless an up-to-date one is kept.
    public func loadRow(_ cardID: Int64) async {
        if let cached = rows[cardID], cached.generation == generation { return }
        let generation = generation
        do {
            let row = try await store.core.browserRowForId(.with { $0.val = cardID })
            rows[cardID] = CachedRow(row: CardRow(id: cardID, row), generation: generation)
        } catch {
            // A card deleted since the search: the next search drops it.
            rows[cardID] = nil
        }
    }

    /// Shows the cards matching the search, then keeps the list current
    /// whenever the collection changes in a way that could alter it, until the
    /// calling task is cancelled. The browse screen runs this in its `.task`.
    public func run() async {
        let changes = store.changes()
        await search()
        for await change in changes where !change.isDisjoint(with: Self.relevantChanges) {
            await search()
        }
    }

    private struct CachedRow {
        let row: CardRow
        let generation: Int
    }
}
