import AnkiProto
import CollectionStore
import CollectionTesting
import DeckOptionsFeature
import Testing

@MainActor
@Suite("Deck options: FSRS", .serialized, .timeLimit(.minutes(1)))
struct FSRSTests {
    @Test("FSRS is collection-wide, retention can override a shared preset, and empty history preserves parameters")
    func savesScopesAndReportsEmptyHistory() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let french = try await store.addDeck(named: "French")
            let model = await openOptions(store, deck: spanish)

            #expect(!model.fsrsEnabled)
            model.fsrsEnabled = true
            model.desiredRetention = 0.92
            model.deckDesiredRetention = 0.85
            model.fsrsHealthCheck = true
            let initialParameters = model.fsrsParameters
            await model.optimizeFSRS()
            #expect(model.fsrsOutcome == .insufficientHistory)
            #expect(model.fsrsParameters == initialParameters)
            #expect(await model.save())

            let edited = await openOptions(store, deck: spanish)
            let shared = await openOptions(store, deck: french)
            #expect(edited.fsrsEnabled && shared.fsrsEnabled)
            #expect(edited.fsrsHealthCheck && shared.fsrsHealthCheck)
            #expect(edited.desiredRetention == 0.92 && shared.desiredRetention == 0.92)
            #expect(edited.deckDesiredRetention == 0.85)
            #expect(shared.deckDesiredRetention == nil)

            edited.fsrsEnabled = false
            #expect(await edited.save())
            #expect(await openOptions(store, deck: french).fsrsEnabled == false)
            #expect(await openOptions(store, deck: spanish).deckDesiredRetention == 0.85)
        }
    }

    @Test("Optimization from real review history changes the draft and persists on save")
    func optimizesReviewedCards() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "French")
            try await store.addFSRSHistory(to: deck, cardCount: 160)
            let model = await openOptions(store, deck: deck)
            model.fsrsEnabled = true

            let defaults = try await store.core.getDeckConfigsForUpdate(.with { $0.did = deck }).defaults.config.fsrsParams6
            var poorParameters = defaults
            poorParameters.replaceSubrange(0..<4, with: [0.01, 0.01, 0.01, 0.01])
            model.fsrsParameterText = poorParameters.map { String($0) }.joined(separator: ", ")
            #expect(model.fsrsParameterError == nil)

            let expected = try await store.core.computeFsrsParams(.with {
                $0.search = #"preset:"Default" -is:suspended"#
                $0.currentParams = poorParameters
                $0.numOfRelearningSteps = 1
            })
            #expect(expected.fsrsItems > 0)

            await model.optimizeFSRS()
            #expect(model.fsrsOutcome == .optimized(healthCheckPassed: nil))
            #expect(model.fsrsParameters == expected.params)
            #expect(model.fsrsParameters.count == 21)
            #expect(model.fsrsParameters != poorParameters)
            #expect(await openOptions(store, deck: deck).fsrsParameters.isEmpty)
            let optimized = model.fsrsParameters
            #expect(await model.save())
            #expect(await openOptions(store, deck: deck).fsrsParameters == optimized)
        }
    }

    @Test("Cancelling an in-flight optimization keeps the draft and stored weights")
    func cancellationKeepsParameters() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "German")
            try await store.addFSRSHistory(to: deck, cardCount: 800)
            let model = await openOptions(store, deck: deck)
            model.fsrsEnabled = true
            let original = model.fsrsParameters

            let optimization = Task { await model.optimizeFSRS() }
            let deadline = ContinuousClock.now + .seconds(3)
            while model.fsrsProgress == nil, model.fsrsOutcome == nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            let wasOptimizing = model.isOptimizingFSRS
            #expect(wasOptimizing)
            #expect(model.fsrsProgress != nil)
            model.cancelFSRSOptimization()
            await optimization.value

            #expect(model.fsrsOutcome == .cancelled)
            #expect(model.fsrsParameters == original)
            #expect(await openOptions(store, deck: deck).fsrsParameters == original)
            #expect(model.canSave)
        }
    }

    @Test("Save and optimize applies pending settings and reloads the preset")
    func savesWhileOptimizingAllPresets() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Portuguese")
            try await store.addFSRSHistory(to: deck, cardCount: 160)
            let model = await openOptions(store, deck: deck)
            model.fsrsEnabled = true
            model.newCardsPerDay = 17
            #expect(await model.saveAndOptimizeAllFSRS())
            #expect(model.hasChanges == false)
            #expect(model.fsrsOutcome == .savedAndOptimized)
            let reopened = await openOptions(store, deck: deck)
            #expect(reopened.newCardsPerDay == 17)
            #expect(reopened.fsrsEnabled)
            #expect(reopened.fsrsParameters.count == 21)
        }
    }

    @Test("Review simulator and retention workload use the draft limits without saving them")
    func simulatesReviewAndWorkload() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let model = await openOptions(store, deck: deck)
            model.fsrsEnabled = true
            #expect(await model.save())
            await model.load()

            model.newCardsPerDay = 3
            var input = model.fsrsSimulationSettings(workload: false)
            input.days = 14
            input.additionalNewCards = 12
            let simulation = try await model.simulateFSRSReviews(input)
            #expect(simulation.dailyNewCount.count == 14)
            #expect(simulation.dailyReviewCount.count == 14)
            #expect(simulation.dailyTimeCost.count == 14)
            #expect(Array(simulation.dailyNewCount.prefix(4)) == [3, 3, 3, 3])

            let workload = try await model.simulateFSRSWorkload(input)
            #expect(workload.memorized.keys.sorted() == Array(70...99))
            #expect(workload.reviewCount[90, default: 0] > 0)
            #expect(await openOptions(store, deck: deck).newCardsPerDay == 20)
        }
    }
}

private extension CollectionStore {
    func addFSRSHistory(to deck: Int64, cardCount: Int) async throws {
        try await addBasicNotes(count: cardCount, toDeck: deck)
        for (index, card) in try await cardIDs().enumerated() {
            try await review(card, rating: .good, daysAgo: 40)
            try await review(card, rating: .good, daysAgo: 40)
            try await review(card, rating: index.isMultiple(of: 4) ? .again : .good, daysAgo: 34)
            try await review(card, rating: index.isMultiple(of: 3) ? .again : .good, daysAgo: 25)
            try await review(card, rating: .good, daysAgo: 5)
        }
    }
}
