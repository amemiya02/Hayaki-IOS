import AnkiCore
import AnkiProto
import CollectionStore
import Foundation

/// Learner-level actions for setting up a test collection. Each goes through
/// the real core, and those that modify the collection go through
/// `CollectionStore.modify(_:)`, so they signal their changes like the app does.
extension CollectionStore {
    /// The names of all decks, parents before children, as the core lists them.
    public func deckNames() async throws -> [String] {
        try await core.getDeckNames(.with {
            $0.skipEmptyDefault = false
            $0.includeFiltered = true
        }).entries.map(\.name).sorted()
    }

    /// Adds a deck; `name` may be a path such as `"Languages::Spanish"`, which
    /// creates missing parents too. Returns the new deck's id.
    @discardableResult
    public func addDeck(named name: String) async throws -> Int64 {
        var deck = try await core.newDeck()
        deck.name = name
        return try await modify(.addDeck(deck)).id
    }

    /// The id of the deck with this full name.
    public func deckID(named name: String) async throws -> Int64 {
        try await core.getDeckIdByName(.with { $0.val = name }).did
    }

    /// Adds `count` notes of the stock Basic note type to a deck and returns
    /// the ids of their cards, one card per note.
    @discardableResult
    public func addBasicNotes(count: Int, toDeck deckID: Int64) async throws -> [Int64] {
        let basic = try await core.getNotetypeIdByName(.with { $0.val = "Basic" })
        let template = try await core.newNote(basic)
        let requests = (0..<count).map { index in
            Anki_Notes_AddNoteRequest.with {
                $0.note = template
                $0.note.fields = ["Question \(index)", "Answer \(index)"]
                $0.deckID = deckID
            }
        }
        let noteIDs = try await modify(.addNotes(.with { $0.requests = requests })).nids
        var cardIDs: [Int64] = []
        for noteID in noteIDs {
            cardIDs += try await core.cardsOfNote(.with { $0.nid = noteID }).cids
        }
        return cardIDs
    }

    /// Makes cards review cards due today, as Anki's "Set Due Date" with 0 days does.
    public func makeDueToday(_ cardIDs: [Int64]) async throws {
        try await modify(.setDueDate(.with {
            $0.cardIds = cardIDs
            $0.days = "0"
        }))
    }

    /// Studies the next card of a deck once, answering it with `rating`, as
    /// the study screen does. Returns the id of the card answered.
    @discardableResult
    public func answerNextCard(inDeck deckID: Int64, rating: Anki_Scheduler_CardAnswer.Rating) async throws -> Int64 {
        try await modify(.setCurrentDeck(.with { $0.did = deckID }))
        let queued = try await core.getQueuedCards(.with { $0.fetchLimit = 1 })
        guard let next = queued.cards.first else {
            throw CoreError(kind: .notFoundError, message: "No card left to study in deck \(deckID).")
        }
        let newState: Anki_Scheduler_SchedulingState = switch rating {
        case .again: next.states.again
        case .hard: next.states.hard
        case .good: next.states.good
        case .easy: next.states.easy
        case .UNRECOGNIZED: next.states.current
        }
        try await modify(.answerCard(.with {
            $0.cardID = next.card.id
            $0.currentState = next.states.current
            $0.newState = newState
            $0.rating = rating
            $0.answeredAtMillis = Int64(Date().timeIntervalSince1970 * 1000)
            $0.millisecondsTaken = 3000
        }))
        return next.card.id
    }
}
