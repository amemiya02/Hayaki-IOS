import AnkiCore
import AnkiProto
import CollectionStore

/// Something the learner can do to all the selected cards at once.
public enum BulkAction: Hashable, Sendable {
    case suspend
    /// Lets suspended (and buried) cards be studied again.
    case unsuspend
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
    /// Carries out an action on every selected card through the core, as one
    /// operation the core can undo, then lists the cards again. On failure,
    /// `failure` holds the core's explanation and nothing is changed.
    public func perform(_ action: BulkAction) async {
        let cardIDs = Array(selection)
        guard !cardIDs.isEmpty else { return }
        failure = nil
        do {
            var cardCount = cardIDs.count
            switch action {
            case .suspend:
                try await store.modify(.buryOrSuspendCards(.with {
                    $0.cardIds = cardIDs
                    $0.mode = .suspend
                }))
            case .unsuspend:
                try await store.modify(.restoreBuriedAndSuspendedCards(.with { $0.cids = cardIDs }))
            case .flag(let flag):
                try await store.modify(.setFlag(.with {
                    $0.cardIds = cardIDs
                    $0.flag = UInt32(flag?.rawValue ?? 0)
                }))
            case .move(let deckID):
                try await store.modify(.setDeck(.with {
                    $0.cardIds = cardIDs
                    $0.deckID = deckID
                }))
            case .delete:
                cardCount = try await summarizeDeletion(of: cardIDs).cardCount
                try await store.modify(.removeNotes(.with { $0.cardIds = cardIDs }))
            }
            let undoName = try await store.undoableAction() ?? ""
            completedAction = CompletedAction(action: action, cardCount: cardCount, undoName: undoName)
        } catch {
            failure = error.message
        }
        await search()
    }

    /// How many notes and cards deleting the selected cards would delete,
    /// for the learner to confirm; nil if the core cannot say.
    public func deletionSummary() async -> DeletionSummary? {
        try? await summarizeDeletion(of: Array(selection))
    }

    /// Undoes the last bulk action, unless the collection was changed in
    /// another way since (which the core would undo instead). Returns whether
    /// it was undone.
    @discardableResult
    public func undoLastAction() async -> Bool {
        guard let completedAction else { return false }
        self.completedAction = nil
        failure = nil
        do {
            guard try await store.undoableAction() == completedAction.undoName else { return false }
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

    private func summarizeDeletion(of cardIDs: [Int64]) async throws(CoreError) -> DeletionSummary {
        let cards = cardIDs.map(String.init).joined(separator: ",")
        let notes = try await store.core.searchNotes(.with { $0.search = "cid:\(cards)" }).ids
        let allCards = try await store.core.searchCards(.with {
            $0.search = "nid:\(notes.map(String.init).joined(separator: ","))"
        }).ids
        return DeletionSummary(noteCount: notes.count, cardCount: allCards.count)
    }
}
