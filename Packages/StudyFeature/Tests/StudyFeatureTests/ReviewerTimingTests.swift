import AnkiCore
import CollectionTesting
import Foundation
import StudyFeature
import Testing

@MainActor
@Suite("Reviewer timing")
struct ReviewerTimingTests {
    @Test("Study progress tracks the remaining queue through Again, a completed card and Undo")
    func queueProgressAndEstimate() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Queue")
            try await store.addBasicNotes(count: 4, toDeck: deck)
            let session = StudySessionModel(store: store, deckID: deck)
            await session.start()
            #expect(session.progress == 0)
            #expect(session.minutesRemaining == 1)

            session.showAnswer()
            await session.answer(.again)
            #expect(session.progress == 0)
            #expect(session.reviewedCount == 1)

            session.showAnswer()
            await session.answer(.easy)
            #expect(session.progress == 0.25)
            #expect(session.reviewedCount == 2)
            await session.undo()
            #expect(session.progress == 0)
        }
    }

    @Test("A leech reports whether the scheduler suspended the card")
    func suspendedLeech() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Leeches")
            let id = try await store.addBasicCard(front: "Difficult", back: "Answer", inDeck: deck)
            try await store.makeReviewCardsDueToday([id], intervalDays: 10)
            var card = try await store.core.getCard(.with { $0.cid = id })
            card.lapses = 7
            let lapsed = card
            try await store.modify(.updateCards(.with { $0.cards = [lapsed] }))
            let session = StudySessionModel(store: store, deckID: deck)
            await session.start()
            session.showAnswer()
            await session.answer(.again)
            #expect(session.leechFeedback == .suspended)
            #expect(try await store.core.getCard(.with { $0.cid = id }).queue == -1)
        }
    }

    @Test("Browse from study searches the current card's nested deck and anchors the card")
    func browseNestedDeck() async throws {
        try await withTemporaryCollection { store in
            let parent = try await store.addDeck(named: "Languages")
            let nested = try await store.addDeck(named: "Languages::Spanish")
            let other = try await store.addDeck(named: "Games::Spanish")
            let displayed = try await store.addBasicCard(front: "gato", back: "cat", inDeck: nested)
            try await store.addBasicCard(front: "Other deck", back: "Other", inDeck: other)
            let session = StudySessionModel(store: store, deckID: parent)
            await session.start()
            guard case .browse(let query, let cardID) = try await session.browseDestination() else {
                Issue.record("Expected a Browse destination for the displayed card")
                return
            }
            #expect(cardID == displayed)
            #expect(try await store.core.searchCards(.with { $0.search = query }).ids == [displayed])
        }
    }

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
