import AnkiCore
import CollectionStore
import CollectionTesting
import StudyFeature

extension CollectionStore {
    /// Moves the cards matching `search` into a deck of their own, due today,
    /// and starts a study session over that deck, so a test can study
    /// particular fixture cards whatever the fixture's scheduling.
    @MainActor
    func studySession(ofCardsMatching search: String) async throws -> StudySessionModel {
        let cardIDs = try await cardIDs(matching: search)
        let deck = try await addDeck(named: "Under test \(cardIDs.first ?? 0)")
        try await modify(.setDeck(.with {
            $0.cardIds = cardIDs
            $0.deckID = deck
        }))
        try await makeDueToday(cardIDs)
        let session = StudySessionModel(store: self, deckID: deck)
        await session.start()
        return session
    }
}
