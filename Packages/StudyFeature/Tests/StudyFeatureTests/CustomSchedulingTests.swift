import AnkiCore
import AnkiProto
import CollectionTesting
import Foundation
@testable import StudyFeature
import Testing

@MainActor
@Suite("Custom scheduling")
struct CustomSchedulingTests {
    @Test("The reviewer uses an accepted custom interval and card data when rating")
    func customizedStatePersistsAfterRating() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Custom Scheduler")
            let created = try await store.addBasicNotes(count: 1, toDeck: deck)
            let cardID = try #require(created.first)
            _ = try await store.core.setConfigString(.with {
                $0.key = .cardStateCustomizer
                $0.value = "states.easy.normal.review.scheduledDays = 12;"
            })
            let model = StudySessionModel(store: store, deckID: deck)
            await model.start()

            let request = try #require(model.customSchedulingRequest)
            #expect(request.cardID == cardID)
            #expect(model.isBusy)
            model.showAnswer()
            #expect(model.state.question != nil)

            var states = try Anki_Scheduler_SchedulingStates(jsonString: request.statesJSON)
            states.easy.normal.review.scheduledDays = 12
            states.easy.customData = #"{"tag":"custom-scheduler"}"#
            await model.applyCustomSchedule(requestID: request.id, json: try states.jsonString())

            #expect(!model.isBusy)
            model.showAnswer()
            await model.answer(.easy)
            let rated = try await store.core.getCard(.with { $0.cid = cardID })
            #expect(rated.interval == 12)
            #expect(rated.customData.contains("custom-scheduler"))
        }
    }

    @Test("A stale scheduler response is ignored and a failed transform recovers the original intervals")
    func staleThenFailedScheduling() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Custom Scheduler")
            try await store.addBasicNotes(count: 1, toDeck: deck)
            _ = try await store.core.setConfigString(.with {
                $0.key = .cardStateCustomizer
                $0.value = "throw new Error('test');"
            })
            let model = StudySessionModel(store: store, deckID: deck)
            await model.start()

            let request = try #require(model.customSchedulingRequest)
            let original = try #require(model.state.question).intervals
            await model.applyCustomSchedule(requestID: UUID(), json: nil)
            #expect(model.customSchedulingRequest?.id == request.id)
            #expect(model.actionError == nil)

            await model.applyCustomSchedule(requestID: request.id, json: nil)
            #expect(model.customSchedulingRequest == nil)
            #expect(model.actionError != nil)
            #expect(model.state.question?.intervals == original)
            model.clearActionError()
            model.showAnswer()
            #expect(model.state.answer != nil)
        }
    }
}
