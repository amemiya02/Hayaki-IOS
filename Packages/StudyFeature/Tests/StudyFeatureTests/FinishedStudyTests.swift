import AnkiCore
import CollectionTesting
import Foundation
import StudyFeature
import Testing

@MainActor
@Suite("Why a study session finished")
struct FinishedStudyTests {
    @Test("A card buried today will be available after the next study day begins")
    func buriedUntilTomorrow() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let cards = try await store.addBasicNotes(count: 1, toDeck: deck)
            try await store.modify(.buryOrSuspendCards(.with {
                $0.cardIds = cards
                $0.mode = .buryUser
            }))

            let session = StudySessionModel(store: store, deckID: deck)
            await session.start()

            let summary = try #require(session.state.finished)
            #expect(summary.reason == .buried)
            #expect(summary.nextDayStartsAt > .now)
        }
    }

    @Test("An empty deck is done and has no buried cards to recover")
    func emptyDeckIsDone() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let session = StudySessionModel(store: store, deckID: deck)
            await session.start()

            let summary = try #require(session.state.finished)
            #expect(summary.reason == .done)
            #expect(!summary.hasBuried)
        }
    }
}
