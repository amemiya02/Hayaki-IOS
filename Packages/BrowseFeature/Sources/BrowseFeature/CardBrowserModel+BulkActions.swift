import AnkiCore
import AnkiProto
import CollectionStore

/// Something the learner can do to all the selected cards at once.
public enum BulkAction: Hashable, Sendable {
    case suspend
    /// Lets suspended (and buried) cards be studied again.
    case unsuspend
    case toggleSuspend
    case toggleBury
    case toggleMark
    case addTags(String)
    case removeTags(String)
    case setDueDate(String)
    case resetProgress(restorePosition: Bool, resetCounts: Bool)
    case reposition(start: UInt32, step: UInt32, randomize: Bool, shiftExisting: Bool)
    case grade(CardDetail.Review.Rating)
    case findAndReplace(search: String, replacement: String, field: String, tags: Bool, regex: Bool, matchCase: Bool, onlySelection: Bool)
    /// Sets a flag, replacing any other; nil takes the flag off.
    case flag(CardRow.Flag?)
    /// Moves the cards to a deck, by id. Cards borrowed by a filtered deck
    /// are moved home first, as Anki does.
    case move(toDeck: Int64)
    /// Deletes the notes of the cards, with all their cards, as Anki's
    /// browser does. Ask first: see `CardBrowserModel.deletionSummary()`.
    case delete
}

/// A bulk action that was carried out and can be undone.
public struct CompletedAction: Equatable, Sendable {
    public let action: BulkAction
    /// How many cards it changed (for a deletion: deleted, which includes
    /// the other cards of the deleted notes).
    public let cardCount: Int
    /// The core's name for the operation, in its language, such as "Set
    /// Flag": what undoing it reverts.
    public let undoName: String
    let undoStep: UInt32
}

/// What deleting the selected cards would delete.
public struct DeletionSummary: Equatable, Sendable {
    /// The notes of the selected cards.
    public let noteCount: Int
    /// All the cards of those notes, selected or not.
    public let cardCount: Int

    public init(noteCount: Int, cardCount: Int) {
        self.noteCount = noteCount
        self.cardCount = cardCount
    }
}

extension CardBrowserModel {
    /// Applies the action to the current selection as a single undoable operation.
    public func perform(_ action: BulkAction) async {
        guard !isPerformingAction else { return }
        let selected = rowIDs.filter { selection.contains($0) }
        let mode = mode
        if case .findAndReplace(_, _, _, _, _, _, false) = action {
            // The unscoped Find and Replace action searches all notes.
        } else if selected.isEmpty {
            return
        }
        isPerformingAction = true
        failure = nil
        completedAction = nil
        defer { isPerformingAction = false }
        do {
            let undoBefore = try await store.core.getUndoStatus()
            let result = try await apply(action, selected: selected, mode: mode)
            let undo = try await store.core.getUndoStatus()
            if !CollectionChange(result.changes).isEmpty, !undo.undo.isEmpty, undo.lastStep != undoBefore.lastStep {
                completedAction = CompletedAction(
                    action: action, cardCount: result.cardCount, undoName: undo.undo, undoStep: undo.lastStep
                )
            }
        } catch {
            failure = error.message
        }
        await search()
    }

    private func apply(_ action: BulkAction, selected: [Int64], mode: Mode) async throws(CoreError)
        -> (changes: Anki_Collection_OpChanges, cardCount: Int)
    {
        switch action {
        case .delete, .toggleMark, .addTags, .removeTags, .findAndReplace:
            return try await applyToNotes(action, selected: selected, mode: mode)
        default:
            let cardIDs = try await cardIDs(for: selected, mode: mode)
            guard !cardIDs.isEmpty else { return (.init(), 0) }
            let changes = try await applyToCards(action, ids: cardIDs)
            return (changes, cardIDs.count)
        }
    }

    private func applyToCards(_ action: BulkAction, ids: [Int64]) async throws(CoreError) -> Anki_Collection_OpChanges {
        switch action {
        case .suspend:
            return try await setCardQueue(.suspend, ids: ids)
        case .unsuspend:
            return try await store.modify(.restoreBuriedAndSuspendedCards(.with { $0.cids = ids }))
        case .toggleSuspend:
            return try await toggleQueue(matches: "is:suspended", otherwise: .suspend, ids: ids)
        case .toggleBury:
            return try await toggleQueue(matches: "is:buried", otherwise: .buryUser, ids: ids)
        case .flag(let flag):
            return try await store.modify(.setFlag(.with {
                $0.cardIds = ids
                $0.flag = UInt32(flag?.rawValue ?? 0)
            })).changes
        case .move(let deckID):
            return try await store.modify(.setDeck(.with {
                $0.cardIds = ids
                $0.deckID = deckID
            })).changes
        case .setDueDate(let days):
            return try await store.modify(.setDueDate(.with {
                $0.cardIds = ids
                $0.days = days
                $0.configKey = .with { $0.key = .setDueBrowser }
            }))
        case .resetProgress(let restorePosition, let resetCounts):
            return try await store.modify(.scheduleCardsAsNew(.with {
                $0.cardIds = ids
                $0.log = true
                $0.context = .browser
                $0.restorePosition = restorePosition
                $0.resetCounts = resetCounts
            }))
        case .reposition(let start, let step, let randomize, let shiftExisting):
            return try await store.modify(.sortCards(.with {
                $0.cardIds = ids
                $0.startingFrom = start
                $0.stepSize = step
                $0.randomize = randomize
                $0.shiftExisting = shiftExisting
            })).changes
        case .grade(let rating):
            return try await store.modify(.gradeNow(.with {
                $0.cardIds = ids
                $0.rating = switch rating {
                case .again: .again
                case .hard: .hard
                case .good: .good
                case .easy: .easy
                }
            }))
        case .delete, .toggleMark, .addTags, .removeTags, .findAndReplace:
            return .init()
        }
    }

    private func applyToNotes(_ action: BulkAction, selected: [Int64], mode: Mode) async throws(CoreError)
        -> (changes: Anki_Collection_OpChanges, cardCount: Int)
    {
        if case let .findAndReplace(search, replacement, field, tags, regex, matchCase, onlySelection) = action {
            let notes = onlySelection ? try await noteIDs(for: selected, mode: mode) : []
            guard !onlySelection || !notes.isEmpty else { return (.init(), 0) }
            let result: Anki_Collection_OpChangesWithCount
            if tags {
                result = try await store.modify(.findAndReplaceTag(.with {
                    $0.noteIds = notes
                    $0.search = search
                    $0.replacement = replacement
                    $0.regex = regex
                    $0.matchCase = matchCase
                }))
            } else {
                result = try await store.modify(.findAndReplace(.with {
                    $0.nids = notes
                    $0.search = search
                    $0.replacement = replacement
                    $0.fieldName = field
                    $0.regex = regex
                    $0.matchCase = matchCase
                }))
            }
            return (result.changes, Int(result.count))
        }
        let notes = try await noteIDs(for: selected, mode: mode)
        guard !notes.isEmpty else { return (.init(), 0) }
        let cardCount = try await cardIDs(for: notes, mode: .notes).count
        let changes: Anki_Collection_OpChanges
        switch action {
        case .delete:
            changes = try await store.modify(.removeNotes(.with { $0.noteIds = notes })).changes
        case .toggleMark:
            let marked = try await store.core.searchNotes(.with {
                $0.search = "\(Self.idSearch("nid", notes)) tag:marked"
            }).ids
            changes = try await setTags("marked", add: marked.count != notes.count, noteIDs: notes)
        case .addTags(let tags):
            changes = try await setTags(tags, add: true, noteIDs: notes)
        case .removeTags(let tags):
            changes = try await setTags(tags, add: false, noteIDs: notes)
        default:
            changes = .init()
        }
        return (changes, cardCount)
    }

    private func setTags(_ tags: String, add: Bool, noteIDs: [Int64]) async throws(CoreError) -> Anki_Collection_OpChanges {
        let request = Anki_Tags_NoteIdsAndTagsRequest.with {
            $0.noteIds = noteIDs
            $0.tags = tags
        }
        return try await store.modify(add ? .addNoteTags(request) : .removeNoteTags(request)).changes
    }

    private func setCardQueue(_ mode: Anki_Scheduler_BuryOrSuspendCardsRequest.Mode, ids: [Int64]) async throws(CoreError)
        -> Anki_Collection_OpChanges
    {
        try await store.modify(.buryOrSuspendCards(.with {
            $0.cardIds = ids
            $0.mode = mode
        })).changes
    }

    private func toggleQueue(matches: String, otherwise: Anki_Scheduler_BuryOrSuspendCardsRequest.Mode, ids: [Int64])
        async throws(CoreError) -> Anki_Collection_OpChanges
    {
        let matches = try await store.core.searchCards(.with {
            $0.search = "\(Self.idSearch("cid", ids)) \(matches)"
        }).ids
        if matches.count == ids.count {
            return try await store.modify(.restoreBuriedAndSuspendedCards(.with { $0.cids = ids }))
        }
        return try await setCardQueue(otherwise, ids: ids)
    }

    /// How many notes and cards deleting the selection would remove.
    public func deletionSummary() async -> DeletionSummary? {
        guard let notes = await selectedNoteIDs(), !notes.isEmpty else { return nil }
        do {
            return DeletionSummary(noteCount: notes.count, cardCount: try await cardIDs(for: notes, mode: .notes).count)
        } catch {
            failure = error.message
            return nil
        }
    }

    /// Undoes the last bulk action, unless the collection was changed in
    /// another way since (which the core would undo instead). Returns whether
    /// it was undone.
    @discardableResult
    public func undoLastAction() async -> Bool {
        guard let completedAction, !isPerformingAction else { return false }
        self.completedAction = nil
        failure = nil
        do {
            let undo = try await store.core.getUndoStatus()
            guard undo.lastStep == completedAction.undoStep, undo.undo == completedAction.undoName else { return false }
            try await store.undo()
        } catch {
            failure = error.message
            return false
        }
        await search()
        return true
    }

    /// Stops offering to undo the last bulk action (the core can still undo
    /// it until something else is done).
    public func dismissCompletedAction() {
        completedAction = nil
    }

    func selectedNoteIDs() async -> [Int64]? {
        do {
            return try await noteIDs(for: Array(selection), mode: mode)
        } catch {
            failure = error.message
            return nil
        }
    }

    func cardID(forRow id: Int64) async -> Int64? {
        if mode == .cards { return id }
        do {
            return try await store.core.cardsOfNote(.with { $0.nid = id }).cids.first
        } catch {
            failure = error.message
            return nil
        }
    }

    func previewCardIDs(selectedOnly: Bool) async -> [Int64] {
        let rows = selectedOnly ? rowIDs.filter { selection.contains($0) } : rowIDs
        do {
            return try await cardIDs(for: rows, mode: mode)
        } catch {
            failure = error.message
            return []
        }
    }

    private func noteIDs(for rows: [Int64], mode: Mode) async throws(CoreError) -> [Int64] {
        if mode == .notes || rows.isEmpty { return rows }
        return try await store.core.searchNotes(.with { $0.search = Self.idSearch("cid", rows) }).ids
    }

    private func cardIDs(for rows: [Int64], mode: Mode) async throws(CoreError) -> [Int64] {
        if mode == .cards || rows.isEmpty { return rows }
        return try await store.core.searchCards(.with { $0.search = Self.idSearch("nid", rows) }).ids
    }

    private static func idSearch(_ key: String, _ ids: [Int64]) -> String {
        "\(key):\(ids.map(String.init).joined(separator: ","))"
    }
}
