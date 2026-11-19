import AnkiProto
import CollectionStore
import CollectionTesting
import DeckOptionsFeature
import Foundation
import Testing

/// Saving must keep every option the screen does not present, so settings
/// made in desktop Anki are never lost. The fixture is a preset as desktop
/// Anki might have left it: non-default values in options this screen does not
/// show, the deck's own limits and the collection-wide settings, all written
/// directly through the core rather than through the model under test.
@MainActor
@Suite("Deck options: preserving what the screen does not show", .timeLimit(.minutes(1)))
struct PreservationTests {
    @Test("A preset loaded and saved without edits is unchanged, down to its modification time")
    func saveWithoutEdits() async throws {
        try await withTemporaryCollection { store in
            let fixture = try await store.addDesktopPreset()
            let before = try await store.snapshot(fixture)

            let model = await openOptions(store, deck: fixture.deckID)
            #expect(model.selectedPreset?.name == "From desktop")
            #expect(model.hasChanges == false)
            #expect(await model.save())

            let after = try await store.snapshot(fixture)
            #expect(after.storedPreset == before.storedPreset)
            #expect(after.screenData == before.screenData)
            #expect(after.deck.normal == before.deck.normal)
        }
    }

    @Test("Editing one option changes only that option", arguments: Edit.allCases)
    func editOneOption(edit: Edit) async throws {
        try await withTemporaryCollection { store in
            let fixture = try await store.addDesktopPreset()
            let before = try await store.snapshot(fixture)

            let model = await openOptions(store, deck: fixture.deckID)
            edit.apply(to: model)
            #expect(model.hasChanges)
            #expect(await model.save())

            let after = try await store.snapshot(fixture)
            // The edited preset: the edited field, plus the modification time
            // and sync number the core stamps on any change.
            var expected = before.storedPreset
            edit.expect(in: &expected.config)
            expected.mtimeSecs = after.storedPreset.mtimeSecs
            expected.usn = after.storedPreset.usn
            #expect(after.storedPreset == expected)
            #expect(after.storedPreset.mtimeSecs >= before.storedPreset.mtimeSecs)

            // Everything else the deck options screen data holds: the other
            // presets, the deck's own limits, the collection-wide settings.
            var expectedScreen = before.screenData
            let index = try #require(expectedScreen.allConfig.firstIndex { $0.config.id == fixture.presetID })
            expectedScreen.allConfig[index].config = after.screenData.allConfig[index].config
            #expect(after.screenData == expectedScreen)
            #expect(after.deck.normal == before.deck.normal)
        }
    }

    @Test("Moving the deck to another preset leaves the fixture preset untouched")
    func switchPresetKeepsOldOne() async throws {
        try await withTemporaryCollection { store in
            let fixture = try await store.addDesktopPreset()
            let before = try await store.snapshot(fixture)

            let model = await openOptions(store, deck: fixture.deckID)
            model.selectedPresetID = try #require(model.presets.first { $0.isDefault }).id
            #expect(await model.save())

            let after = try await store.snapshot(fixture)
            #expect(after.storedPreset == before.storedPreset)
            #expect(after.screenData.newCardsIgnoreReviewLimit == true)
            #expect(after.screenData.applyAllParentLimits == true)
            #expect(after.screenData.cardStateCustomizer == before.screenData.cardStateCustomizer)
            #expect(after.screenData.currentDeck.limits == before.screenData.currentDeck.limits)
        }
    }

    @Test("Saving a preset with FSRS 5 weights keeps its legacy weights and effective behavior")
    func preservesLegacyFSRSWeights() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Legacy weights")
            let options = try await store.core.getDeckConfigsForUpdate(.with { $0.did = deck })
            let presetID = options.currentDeck.configID
            let defaults = options.defaults.config.fsrsParams6
            let weights = Array(defaults.prefix(19))
            let legacy = try await store.core.getDeckConfigLegacy(.with { $0.dcid = presetID })
            var payload = try #require(JSONSerialization.jsonObject(with: legacy.json) as? [String: Any])
            payload["fsrsParams5"] = weights
            let encoded = try JSONSerialization.data(withJSONObject: payload)
            _ = try await store.core.addOrUpdateDeckConfigLegacy(.with { $0.json = encoded })

            let raw = try await store.core.getDeckConfig(.with { $0.dcid = presetID })
            #expect(raw.config.fsrsParams5 == weights)
            #expect(raw.config.fsrsParams6.isEmpty)
            let model = await openOptions(store, deck: deck)
            #expect(model.fsrsParameters == weights)

            model.applyAllParentLimits = true
            #expect(await model.save())
            let saved = try await store.core.getDeckConfig(.with { $0.dcid = presetID })
            #expect(saved.config.fsrsParams5 == weights)
            #expect(await openOptions(store, deck: deck).fsrsParameters == weights)
        }
    }

    /// One presented option, edited on the screen, and the field of the core's
    /// message it must change.
    enum Edit: String, CaseIterable, CustomTestStringConvertible {
        case newCardsPerDay, reviewsPerDay, learningSteps, relearningSteps
        case newCardGatherOrder, newCardSortOrder, newReviewMix, interdayLearningReviewMix, reviewSortOrder
        case buryNewSiblings, buryReviewSiblings, buryInterdayLearningSiblings

        var testDescription: String { rawValue }

        @MainActor
        func apply(to model: DeckOptionsModel) {
            switch self {
            case .newCardsPerDay: model.newCardsPerDay = 16
            case .reviewsPerDay: model.reviewsPerDay = 321
            case .learningSteps: model.learningSteps = "3m 30m"
            case .relearningSteps: model.relearningSteps = "45m"
            case .newCardGatherOrder: model.newCardGatherOrder = .randomNotes
            case .newCardSortOrder: model.newCardSortOrder = .noSort
            case .newReviewMix: model.newReviewMix = .afterReviews
            case .interdayLearningReviewMix: model.interdayLearningReviewMix = .beforeReviews
            case .reviewSortOrder: model.reviewSortOrder = .added
            case .buryNewSiblings: model.buryNewSiblings = false
            case .buryReviewSiblings: model.buryReviewSiblings = false
            case .buryInterdayLearningSiblings: model.buryInterdayLearningSiblings = false
            }
        }

        func expect(in config: inout Anki_DeckConfig_DeckConfig.Config) {
            switch self {
            case .newCardsPerDay: config.newPerDay = 16
            case .reviewsPerDay: config.reviewsPerDay = 321
            case .learningSteps: config.learnSteps = [3, 30]
            case .relearningSteps: config.relearnSteps = [45]
            case .newCardGatherOrder: config.newCardGatherPriority = .randomNotes
            case .newCardSortOrder: config.newCardSortOrder = .noSort
            case .newReviewMix: config.newMix = .afterReviews
            case .interdayLearningReviewMix: config.interdayLearningMix = .beforeReviews
            case .reviewSortOrder: config.reviewOrder = .added
            case .buryNewSiblings: config.buryNew = false
            case .buryReviewSiblings: config.buryReviews = false
            case .buryInterdayLearningSiblings: config.buryInterdayLearning = false
            }
        }
    }
}

/// A preset set up as desktop Anki might have left it, and the deck using it.
struct DesktopPreset {
    let deckID: Int64
    let presetID: Int64
}

/// What the core holds for the deck options of a deck.
struct DeckOptionsSnapshot {
    /// The preset as stored, read directly.
    let storedPreset: Anki_DeckConfig_DeckConfig
    /// Everything the core gives the deck options screen.
    let screenData: Anki_DeckConfig_DeckConfigsForUpdate
    let deck: Anki_Decks_Deck
}

extension CollectionStore {
    func snapshot(_ fixture: DesktopPreset) async throws -> DeckOptionsSnapshot {
        DeckOptionsSnapshot(
            storedPreset: try await core.getDeckConfig(.with { $0.dcid = fixture.presetID }),
            screenData: try await core.getDeckConfigsForUpdate(.with { $0.did = fixture.deckID }),
            deck: try await core.getDeck(.with { $0.did = fixture.deckID })
        )
    }

    /// Adds a deck with a preset that has a non-default value in every option
    /// the deck options screen does not present, as well as the deck's own
    /// limits and non-default collection-wide settings. Written straight
    /// through the core, not through the model under test.
    func addDesktopPreset() async throws -> DesktopPreset {
        let deckID = try await addDeck(named: "Japanese")
        // Cards in the deck, so changes that touch cards would show.
        try await addBasicNotes(count: 3, toDeck: deckID)
        let current = try await core.getDeckConfigsForUpdate(.with { $0.did = deckID })

        var preset = current.defaults
        preset.id = 0
        preset.name = "From desktop"
        preset.config.with {
            // Presented options, set away from their defaults too.
            $0.newPerDay = 15
            $0.reviewsPerDay = 150
            $0.learnSteps = [2, 20, 120]
            $0.relearnSteps = [5, 60]
            $0.newCardGatherPriority = .highestPosition
            $0.newCardSortOrder = .templateThenRandom
            $0.newMix = .beforeReviews
            $0.interdayLearningMix = .afterReviews
            $0.reviewOrder = .deckThenDay
            $0.buryNew = true
            $0.buryReviews = true
            $0.buryInterdayLearning = true
            // Options the screen does not present.
            $0.newPerDayMinimum = 2
            $0.initialEase = 2.1
            $0.easyMultiplier = 1.4
            $0.hardMultiplier = 1.1
            $0.lapseMultiplier = 0.3
            $0.intervalMultiplier = 0.9
            $0.maximumReviewInterval = 3650
            $0.minimumLapseInterval = 2
            $0.graduatingIntervalGood = 3
            $0.graduatingIntervalEasy = 6
            $0.newCardInsertOrder = .random
            $0.leechAction = .tagOnly
            $0.leechThreshold = 6
            $0.disableAutoplay = true
            $0.capAnswerTimeToSecs = 45
            $0.showTimer = true
            $0.stopTimerOnAnswer = true
            $0.secondsToShowQuestion = 12
            $0.secondsToShowAnswer = 8
            $0.questionAction = .showReminder
            $0.answerAction = .answerGood
            $0.waitForAudio = false
            $0.skipQuestionWhenReplayingAnswer = true
            $0.desiredRetention = 0.85
            $0.historicalRetention = 0.8
            $0.ignoreRevlogsBeforeDate = "2024-01-01"
            $0.easyDaysPercentages = [1, 1, 1, 1, 1, 0.5, 0]
            $0.paramSearch = "deck:Japanese -is:suspended"
            // FSRS parameters: Anki's defaults, but stored, where a new preset
            // has none.
            $0.fsrsParams6 = current.defaults.config.fsrsParams6
            // Settings of add-ons and newer Anki versions, kept as JSON.
            $0.other = Data(#"{"addonSetting":42,"futureOption":[1,2]}"#.utf8)
        }
        #expect(preset.config.fsrsParams6.isEmpty == false)

        var request = Anki_DeckConfig_UpdateDeckConfigsRequest()
        request.targetDeckID = deckID
        request.configs = [preset]
        request.mode = .normal
        request.limits = .with {
            // The deck's own limits: a review limit for this deck only, and a
            // new card limit for today only.
            $0.review = 77
            $0.newToday = 3
            $0.newTodayActive = true
            $0.desiredRetention = 0.92
        }
        request.newCardsIgnoreReviewLimit = true
        request.applyAllParentLimits = true
        request.cardStateCustomizer = "// customised on desktop"
        request.fsrs = false
        request.fsrsHealthCheck = !current.fsrsHealthCheck
        try await modify(.updateDeckConfigs(request))

        let saved = try await core.getDeckConfigsForUpdate(.with { $0.did = deckID })
        let presetID = saved.currentDeck.configID
        // The fixture really is as described: every value above was stored.
        let stored = try await core.getDeckConfig(.with { $0.dcid = presetID })
        #expect(stored.name == "From desktop")
        #expect(stored.config.other == preset.config.other)
        #expect(stored.config.maximumReviewInterval == 3650)
        #expect(saved.currentDeck.limits.review == 77)
        #expect(saved.currentDeck.limits.newToday == 3)
        #expect(saved.newCardsIgnoreReviewLimit)
        #expect(saved.applyAllParentLimits)
        return DesktopPreset(deckID: deckID, presetID: presetID)
    }
}

private extension Anki_DeckConfig_DeckConfig.Config {
    mutating func with(_ change: (inout Self) -> Void) {
        change(&self)
    }
}
