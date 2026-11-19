import CollectionTesting
@testable import StudyFeature
import Testing

@MainActor
@Suite("Returning to the reviewer")
struct ReviewerReturnTests {
    @Test("Returning from another screen preserves the answer until an external change removes its card")
    func refreshesQueueAfterExternalChanges() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Reviewer")
            try await store.addBasicNotes(count: 2, toDeck: deck)
            let model = StudySessionModel(store: store, deckID: deck)
            await model.start()
            let first = try #require(model.state.question)
            model.showAnswer()

            await model.refreshAfterExternalChanges()
            #expect(model.state.answer?.id == first.id)
            #expect(model.counts.new == 2)

            try await store.suspend([first.id])
            await model.refreshAfterExternalChanges()

            #expect(model.state.question?.id != nil)
            #expect(model.state.question?.id != first.id)
            #expect(model.counts.new == 1)
        }
    }
}
