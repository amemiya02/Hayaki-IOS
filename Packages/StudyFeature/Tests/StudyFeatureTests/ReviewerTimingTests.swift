import AnkiCore
import CollectionTesting
import Foundation
import StudyFeature
import Testing

@MainActor
@Suite("Reviewer timing")
struct ReviewerTimingTests {
    @Test("Deck timing and collection timebox are applied through the reviewer")
    func deckAndCollectionTiming() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Timed")
            _ = try await store.addBasicNotes(count: 2, toDeck: deck)
            var preferences = try await store.core.getPreferences()
            preferences.reviewing.timeLimitSecs = 60
            preferences.reviewing.showRemainingDueCounts = false
            try await store.modify(.setPreferences(preferences))
            let options = try await store.core.getDeckConfigsForUpdate(.with { $0.did = deck })
            var config = try #require(options.allConfig.first { $0.config.id == options.currentDeck.configID }).config
            config.config.showTimer = true
            config.config.stopTimerOnAnswer = true
            config.config.secondsToShowQuestion = 2.5
            config.config.secondsToShowAnswer = 3
            config.config.answerAction = .answerGood
            config.config.waitForAudio = true
            try await store.modify(.updateDeckConfigs(.with {
                $0.targetDeckID = deck
                $0.configs = [config]
            }))

            let session = StudySessionModel(store: store, deckID: deck)
            await session.start()
            #expect(session.showsAnswerTimer)
            #expect(!session.showsRemainingCounts)
            #expect(session.autoAdvancePlan?.command == .showAnswer)
            #expect(session.autoAdvancePlan?.delay == .milliseconds(2500))
            #expect(session.autoAdvancePlan?.waitForAudio == true)
            await session.perform(.showAnswer)
            #expect(session.autoAdvancePlan?.command == .rateGood)
            #expect(session.answerTimer(at: .now) == session.answerTimer(at: .now + .seconds(4)))
            await session.perform(.rateGood)

            let future = ContinuousClock.now + .seconds(65)
            #expect(session.timeboxProgress(at: future)?.reviewed == 1)
            #expect(session.timeboxProgress(at: future)?.limit == .seconds(60))
            session.restartTimebox(at: future)
            #expect(session.timeboxProgress(at: future) == nil)
        }
    }
}
