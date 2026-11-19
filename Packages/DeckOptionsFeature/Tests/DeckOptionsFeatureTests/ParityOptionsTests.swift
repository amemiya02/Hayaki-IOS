import AnkiProto
import CollectionStore
import CollectionTesting
import DeckOptionsFeature
import Foundation
import Testing

@MainActor
@Suite("Deck options: parity sections", .timeLimit(.minutes(1)))
struct ParityOptionsTests {
    @Test("Daily limits keep separate shared, deck-only, and today-only values")
    func preservesScopedLimits() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "French")
            let neighbor = try await store.addDeck(named: "Spanish")
            let model = await openOptions(store, deck: deck)
            model.newCardsPerDay = 30
            model.reviewsPerDay = 270
            model.deckNewCardsLimit = 20
            model.deckReviewsLimit = 170
            model.todayNewCardsLimit = 2
            model.todayReviewsLimit = 7
            model.newCardsIgnoreReviewLimit = true
            model.applyAllParentLimits = true
            #expect(await model.save())

            let saved = try await store.core.getDeckConfigsForUpdate(.with { $0.did = deck })
            let limits = saved.currentDeck.limits
            #expect(limits.hasNew && limits.new == 20)
            #expect(limits.hasReview && limits.review == 170)
            #expect(limits.newTodayActive && limits.newToday == 2)
            #expect(limits.reviewTodayActive && limits.reviewToday == 7)
            #expect(saved.newCardsIgnoreReviewLimit && saved.applyAllParentLimits)

            let other = await openOptions(store, deck: neighbor)
            #expect(other.newCardsPerDay == 30 && other.reviewsPerDay == 270)
            #expect(other.deckNewCardsLimit == nil && other.deckReviewsLimit == nil)
            #expect(other.todayNewCardsLimit == nil && other.todayReviewsLimit == nil)

            let edited = await openOptions(store, deck: deck)
            edited.todayNewCardsLimit = nil
            edited.deckReviewsLimit = nil
            #expect(await edited.save())
            let reopened = await openOptions(store, deck: deck)
            #expect(reopened.todayNewCardsLimit == nil && reopened.deckReviewsLimit == nil)
            #expect(reopened.deckNewCardsLimit == 20 && reopened.todayReviewsLimit == 7)
        }
    }

    @Test("New, lapse, timer, audio, auto-advance, Easy Days, and advanced edits round-trip together")
    func editsAllPresetSections() async throws {
        try await withTemporaryCollection { store in
            let fixture = try await store.addDesktopPreset()
            let before = try await store.snapshot(fixture)
            let model = await openOptions(store, deck: fixture.deckID)
            let cutoff = try #require(Calendar.current.date(from: DateComponents(year: 2023, month: 5, day: 3)))

            model.newCardInsertionOrder = .due
            model.graduatingInterval = 7
            model.easyGraduatingInterval = 12
            model.minimumLapseInterval = 3
            model.leechThreshold = 5
            model.leechAction = .suspend
            model.maximumAnswerSeconds = 75
            model.showAnswerTimer = false
            model.stopTimerOnAnswer = false
            model.automaticallyPlayAudio = true
            model.skipQuestionAudioWhenReplayingAnswer = false
            model.secondsToShowQuestion = 3.2
            model.secondsToShowAnswer = 4.1
            model.waitForAudio = true
            model.questionAction = .showAnswer
            model.answerAction = .answerAgain
            model.easyDaysPercentages = [0, 0.5, 1, 1, 1, 1, 1]
            model.maximumReviewInterval = 7000
            model.initialEase = 2.3
            model.easyMultiplier = 1.6
            model.hardMultiplier = 1.2
            model.intervalMultiplier = 0.8
            model.lapseMultiplier = 0.2
            model.fsrsEnabled = true
            model.historicalRetention = 0.87
            model.ignoreFSRSHistoryBefore = cutoff
            model.customScheduling = "// retained for all decks"
            #expect(await model.save())

            let reopened = await openOptions(store, deck: fixture.deckID)
            #expect(reopened.newCardInsertionOrder == .due)
            #expect(reopened.secondsToShowQuestion == 3.2)
            #expect(reopened.ignoreFSRSHistoryBefore == cutoff)
            #expect(reopened.easyDaysPercentages == [0, 0.5, 1, 1, 1, 1, 1])
            #expect(reopened.customScheduling == "// retained for all decks")

            let after = try await store.snapshot(fixture)
            var expected = before.storedPreset.config
            expected.newCardInsertOrder = .due
            expected.graduatingIntervalGood = 7
            expected.graduatingIntervalEasy = 12
            expected.minimumLapseInterval = 3
            expected.leechThreshold = 5
            expected.leechAction = .suspend
            expected.capAnswerTimeToSecs = 75
            expected.showTimer = false
            expected.stopTimerOnAnswer = false
            expected.disableAutoplay = false
            expected.skipQuestionWhenReplayingAnswer = false
            expected.secondsToShowQuestion = 3.2
            expected.secondsToShowAnswer = 4.1
            expected.waitForAudio = true
            expected.questionAction = .showAnswer
            expected.answerAction = .answerAgain
            expected.easyDaysPercentages = [0, 0.5, 1, 1, 1, 1, 1]
            expected.maximumReviewInterval = 7000
            expected.initialEase = 2.3
            expected.easyMultiplier = 1.6
            expected.hardMultiplier = 1.2
            expected.intervalMultiplier = 0.8
            expected.lapseMultiplier = 0.2
            expected.historicalRetention = 0.87
            expected.ignoreRevlogsBeforeDate = "2023-05-03"
            #expect(after.storedPreset.config == expected)
            #expect(after.deck.normal == before.deck.normal)
            #expect(after.screenData.cardStateCustomizer == "// retained for all decks")
        }
    }
}
