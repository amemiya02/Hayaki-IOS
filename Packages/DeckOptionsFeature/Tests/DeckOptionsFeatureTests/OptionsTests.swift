import AnkiProto
import CollectionStore
import CollectionTesting
import DeckOptionsFeature
import Foundation
import Testing

@MainActor
@Suite("Deck options: scheduling options", .timeLimit(.minutes(1)))
struct OptionsTests {
    @Test("Daily limits for new cards and reviews are saved to the preset")
    func dailyLimits() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let model = await openOptions(store, deck: spanish)
            #expect(model.newCardsPerDay == 20)
            #expect(model.reviewsPerDay == 200)

            model.newCardsPerDay = 5
            model.reviewsPerDay = 50
            #expect(await model.save())

            let reopened = await openOptions(store, deck: spanish)
            #expect(reopened.newCardsPerDay == 5)
            #expect(reopened.reviewsPerDay == 50)
        }
    }

    @Test("Daily limits stay within what Anki accepts, 0 to 9999")
    func dailyLimitsAreBounded() async throws {
        try await withTemporaryCollection { store in
            let model = await openOptions(store, deck: try await store.addDeck(named: "Spanish"))
            model.newCardsPerDay = 100_000
            model.reviewsPerDay = -3
            #expect(model.newCardsPerDay == 9999)
            #expect(model.reviewsPerDay == 0)
        }
    }

    @Test("Learning and relearning steps are typed as delays and saved")
    func steps() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let model = await openOptions(store, deck: spanish)
            #expect(model.learningSteps == "1m 10m")
            #expect(model.relearningSteps == "10m")

            model.learningSteps = "30s 15m 2h 1d"
            model.relearningSteps = "90s  20"
            #expect(model.learningStepsError == nil)
            #expect(model.relearningStepsError == nil)
            #expect(await model.save())

            let reopened = await openOptions(store, deck: spanish)
            #expect(reopened.learningSteps == "30s 15m 2h 1d")
            // A step without a unit is in minutes.
            #expect(reopened.relearningSteps == "90s 20m")
        }
    }

    @Test("No relearning steps at all is allowed")
    func emptySteps() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let model = await openOptions(store, deck: spanish)
            model.relearningSteps = ""
            #expect(model.relearningStepsError == nil)
            #expect(await model.save())
            #expect(await openOptions(store, deck: spanish).relearningSteps == "")
        }
    }

    @Test(
        "Steps that are not delays are rejected with a message, and nothing is saved",
        arguments: ["1m ten", "0m", "-5m", "10x", "1e3", "m"]
    )
    func invalidSteps(typed: String) async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let model = await openOptions(store, deck: spanish)

            model.learningSteps = typed
            #expect(model.learningSteps == typed)
            let error = try #require(model.learningStepsError)
            #expect(error.contains("is not a step"))
            #expect(model.canSave == false)
            #expect(await model.save() == false)

            #expect(await openOptions(store, deck: spanish).learningSteps == "1m 10m")
        }
    }

    @Test("The message names the part of the steps that is wrong")
    func invalidStepIsNamed() async throws {
        try await withTemporaryCollection { store in
            let model = await openOptions(store, deck: try await store.addDeck(named: "Spanish"))
            model.relearningSteps = "10m soon 1d"
            #expect(model.relearningStepsError?.contains("“soon”") == true)

            model.relearningSteps = "10m 1d"
            #expect(model.relearningStepsError == nil)
            #expect(model.canSave)
        }
    }

    @Test("Display order options are saved to the preset")
    func displayOrder() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let model = await openOptions(store, deck: spanish)
            #expect(model.newCardGatherOrder == .deck)
            #expect(model.newCardSortOrder == .template)
            #expect(model.newReviewMix == .mixWithReviews)
            #expect(model.interdayLearningReviewMix == .mixWithReviews)
            #expect(model.reviewSortOrder == .day)

            model.newCardGatherOrder = .randomCards
            model.newCardSortOrder = .randomCard
            model.newReviewMix = .beforeReviews
            model.interdayLearningReviewMix = .afterReviews
            model.reviewSortOrder = .intervalsDescending
            #expect(await model.save())

            let reopened = await openOptions(store, deck: spanish)
            #expect(reopened.newCardGatherOrder == .randomCards)
            #expect(reopened.newCardSortOrder == .randomCard)
            #expect(reopened.newReviewMix == .beforeReviews)
            #expect(reopened.interdayLearningReviewMix == .afterReviews)
            #expect(reopened.reviewSortOrder == .intervalsDescending)
        }
    }

    @Test("Burying options are saved to the preset")
    func burying() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let model = await openOptions(store, deck: spanish)
            #expect(model.buryNewSiblings == false)
            #expect(model.buryReviewSiblings == false)
            #expect(model.buryInterdayLearningSiblings == false)

            model.buryNewSiblings = true
            model.buryReviewSiblings = true
            model.buryInterdayLearningSiblings = true
            #expect(await model.save())

            let reopened = await openOptions(store, deck: spanish)
            #expect(reopened.buryNewSiblings)
            #expect(reopened.buryReviewSiblings)
            #expect(reopened.buryInterdayLearningSiblings)
        }
    }

    @Test("Options shown are those of the chosen preset")
    func optionsFollowPreset() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let model = await openOptions(store, deck: spanish)
            let defaultPreset = try #require(model.selectedPreset).id
            model.addPreset(named: "Intensive")
            model.newCardsPerDay = 50
            model.learningSteps = "1m oops"

            model.selectedPresetID = defaultPreset
            #expect(model.newCardsPerDay == 20)
            #expect(model.learningSteps == "1m 10m")
            #expect(model.learningStepsError == nil)
            // The other preset's mistyped steps still prevent saving.
            #expect(model.canSave == false)
        }
    }

    @Test("A lower new card limit shows in the deck's counts and its next study session")
    func newLimitTakesEffect() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            try await store.addBasicNotes(count: 30, toDeck: spanish)
            #expect(try await store.newCount(of: spanish) == 20)

            let model = await openOptions(store, deck: spanish)
            model.newCardsPerDay = 5
            #expect(await model.save())

            #expect(try await store.newCount(of: spanish) == 5)
            #expect(try await store.queuedNewCount(in: spanish) == 5)
        }
    }

    @Test("Saving signals a deck options change, so a shown deck list updates")
    func saveSignalsChange() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let changes = store.changes()
            let model = await openOptions(store, deck: spanish)
            model.newCardsPerDay = 5
            #expect(await model.save())

            var iterator = changes.makeAsyncIterator()
            let change = try #require(await iterator.next())
            #expect(change.contains(.deckConfig))
        }
    }

    @Test("New learning steps decide when a failed new card comes back")
    func learningStepsTakeEffect() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            try await store.addBasicNotes(count: 1, toDeck: spanish)
            #expect(try await store.againDelay(in: spanish) == 60)

            let model = await openOptions(store, deck: spanish)
            model.learningSteps = "30m 1d"
            #expect(await model.save())

            #expect(try await store.againDelay(in: spanish) == 30 * 60)
        }
    }
}

extension CollectionStore {
    /// The new count the deck list shows for a deck today.
    func newCount(of deckID: Int64) async throws -> Int {
        let tree = try await core.deckTree(.with { $0.now = Int64(Date().timeIntervalSince1970) })
        let node = try #require(tree.children.first { $0.deckID == deckID })
        return Int(node.newCount)
    }

    /// How many new cards a study session of the deck would show today.
    func queuedNewCount(in deckID: Int64) async throws -> Int {
        try await modify(.setCurrentDeck(.with { $0.did = deckID }))
        return Int(try await core.getQueuedCards(.with { $0.fetchLimit = 1 }).newCount)
    }

    /// In how many seconds the next card of the deck comes back if the
    /// learner answers Again, while it is still learning.
    func againDelay(in deckID: Int64) async throws -> UInt32 {
        try await modify(.setCurrentDeck(.with { $0.did = deckID }))
        let next = try #require(try await core.getQueuedCards(.with { $0.fetchLimit = 1 }).cards.first)
        return next.states.again.normal.learning.scheduledSecs
    }
}
