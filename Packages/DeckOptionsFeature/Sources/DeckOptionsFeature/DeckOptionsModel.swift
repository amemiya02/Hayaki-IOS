import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Observation

/// Identifies a preset on the deck options screen. A preset added on the
/// screen has no id in the collection until it is saved, so it gets a
/// temporary negative one.
public struct PresetID: Hashable, Sendable {
    let rawValue: Int64
}

/// A preset as the deck options screen lists it.
public struct PresetSummary: Identifiable, Equatable, Sendable {
    public let id: PresetID
    public let name: String
    /// How many decks use the preset once the screen's changes are saved,
    /// counting this deck if it uses it.
    public let deckCount: Int
    /// The Default preset, which every collection has and which cannot be
    /// deleted.
    public let isDefault: Bool
}

/// The deck options screen: a deck's preset and the options it sets.
///
/// The model edits the core's own deck options messages in place: it keeps
/// what `GetDeckConfigsForUpdate` returned, changes only the fields the
/// screen presents, and sends those same messages back through
/// `UpdateDeckConfigs`. Every option the screen does not present therefore
/// reaches the core exactly as the core sent it, so settings made in desktop
/// Anki or AnkiDroid are never lost.
///
/// Sections live in their own files as extensions of this model, each over
/// the selected preset's `Config` (`selectedConfig`) or the collection-wide
/// settings (`settings`).
@MainActor
@Observable
public final class DeckOptionsModel {
    public enum State: Equatable {
        case loading
        case loaded
        case failed(message: String)
    }

    public let deckID: Int64
    public private(set) var state: State = .loading
    /// The deck's full name, such as "Languages::Spanish".
    public private(set) var deckName = ""
    /// Why the last save failed, in the core's words; nil after a save
    /// succeeds.
    public private(set) var saveError: String?

    /// What the core sent for this screen. Its collection-wide settings and
    /// the deck's own limits are sent back on save; a section that presents
    /// one of the collection-wide settings edits it here.
    var settings = Anki_DeckConfig_DeckConfigsForUpdate()
    /// Whether the scheduler should reschedule cards when saving; only FSRS
    /// settings set it.
    var fsrsReschedule = false
    public internal(set) var fsrsOutcome: FSRSOutcome?
    public internal(set) var fsrsProgress: Anki_Collection_ComputeParamsProgress?
    public internal(set) var isCancellingFSRS = false
    var fsrsOptimization: LongOperation<Anki_Scheduler_ComputeFsrsParamsResponse>?
    var entries: [PresetEntry] = []
    var selectedID = PresetID(rawValue: 0)
    /// Text being typed into a steps field, kept while the learner edits it.
    var stepsDrafts: [StepsDraftKey: String] = [:]
    var fsrsParameterDrafts: [PresetID: String] = [:]

    @ObservationIgnored let store: CollectionStore
    @ObservationIgnored private var loadedSettings = Anki_DeckConfig_DeckConfigsForUpdate()
    @ObservationIgnored var loadedSelectedID = PresetID(rawValue: 0)
    @ObservationIgnored private var removedConfigIDs: [Int64] = []
    @ObservationIgnored private var nextUnsavedID: Int64 = -1

    /// The id of the Default preset in every collection.
    private static let defaultConfigID: Int64 = 1

    public init(store: CollectionStore, deckID: Int64) {
        self.store = store
        self.deckID = deckID
    }

    /// Reads the deck's options from the core. Edits made since the last
    /// load are discarded.
    public func load() async {
        do {
            let loaded = try await store.core.getDeckConfigsForUpdate(.with { $0.did = deckID })
            settings = loaded
            loadedSettings = loaded
            entries = loaded.allConfig.map { item in
                PresetEntry(
                    id: PresetID(rawValue: item.config.id),
                    config: item.config,
                    saved: item.config,
                    savedDeckCount: Int(item.useCount)
                )
            }
            selectedID = PresetID(rawValue: loaded.currentDeck.configID)
            loadedSelectedID = selectedID
            removedConfigIDs = []
            stepsDrafts = [:]
            fsrsParameterDrafts = [:]
            deckName = loaded.currentDeck.name
            saveError = nil
            fsrsReschedule = false
            resetFSRSFeedback()
            state = .loaded
        } catch {
            state = .failed(message: error.message)
        }
    }

    // MARK: Presets

    /// Every preset, sorted by name.
    public var presets: [PresetSummary] {
        entries
            .map { entry in
                PresetSummary(
                    id: entry.id,
                    name: entry.config.name,
                    deckCount: deckCount(of: entry),
                    isDefault: entry.id.rawValue == Self.defaultConfigID
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The preset this deck uses.
    public var selectedPreset: PresetSummary? {
        presets.first { $0.id == selectedID }
    }

    /// The preset this deck uses; set it to make the deck use another one.
    public var selectedPresetID: PresetID {
        get { selectedID }
        set {
            guard entries.contains(where: { $0.id == newValue }) else { return }
            selectedID = newValue
            resetFSRSFeedback()
        }
    }

    /// Adds a preset with Anki's default options and makes this deck use it.
    /// A name of only spaces is ignored.
    public func addPreset(named name: String) {
        guard !Self.cleanName(name).isEmpty else { return }
        var config = settings.defaults
        config.id = 0
        config.name = name
        insertUnsaved(config)
    }

    /// Adds a copy of the selected preset and makes this deck use it. A name
    /// of only spaces is ignored.
    public func cloneSelectedPreset(named name: String) {
        guard !Self.cleanName(name).isEmpty, var config = selectedEntry?.config else { return }
        config.id = 0
        config.mtimeSecs = 0
        config.usn = 0
        config.name = name
        insertUnsaved(config)
    }

    /// Renames the selected preset. A name of only spaces is ignored.
    public func renameSelectedPreset(to name: String) {
        let name = Self.cleanName(name)
        guard !name.isEmpty, let index = selectedIndex else { return }
        entries[index].config.name = name
    }

    /// Whether the selected preset can be deleted: every preset but Default.
    public var canDeleteSelectedPreset: Bool {
        selectedID.rawValue != Self.defaultConfigID
    }

    /// Deletes the selected preset. This deck, and every other deck that used
    /// it, then use the Default preset.
    public func deleteSelectedPreset() {
        guard canDeleteSelectedPreset, let index = selectedIndex else { return }
        let entry = entries.remove(at: index)
        if entry.saved != nil {
            removedConfigIDs.append(entry.id.rawValue)
        }
        stepsDrafts = stepsDrafts.filter { $0.key.preset != entry.id }
        fsrsParameterDrafts[entry.id] = nil
        selectedID = entries.first { $0.id.rawValue == Self.defaultConfigID }?.id ?? entries[0].id
    }

    // MARK: Saving

    /// Whether anything differs from what was loaded.
    public var hasChanges: Bool {
        selectedID != loadedSelectedID
            || !removedConfigIDs.isEmpty
            || entries.contains { $0.config != $0.saved }
            || settings != loadedSettings
            || fsrsReschedule
            || hasInvalidSteps
            || hasInvalidFSRSParameters
    }

    /// Whether every field holds a valid value, so the options can be saved.
    public var canSave: Bool {
        state == .loaded && !hasInvalidSteps && !hasInvalidFSRSParameters && !isOptimizingFSRS
    }

    /// Saves the options through the core, which applies them to this deck
    /// and to every deck sharing an edited preset. Returns whether it worked;
    /// on failure `saveError` says why and the edits are kept.
    @discardableResult
    public func save() async -> Bool {
        guard canSave, let selected = selectedEntry else { return false }
        do {
            var request = Anki_DeckConfig_UpdateDeckConfigsRequest()
            request.targetDeckID = deckID
            request.removedConfigIds = removedConfigIDs
            // Only presets that changed, then the one the deck uses, which
            // the core requires last.
            let edited = entries.filter { $0.id != selectedID && $0.config != $0.saved }.map(\.config)
            request.configs = edited + [try await configForSaving(selected)]
            request.mode = .normal
            request.limits = Self.limitsForSaving(settings.currentDeck.limits)
            request.cardStateCustomizer = settings.cardStateCustomizer
            request.newCardsIgnoreReviewLimit = settings.newCardsIgnoreReviewLimit
            request.applyAllParentLimits = settings.applyAllParentLimits
            request.fsrs = settings.fsrs
            request.fsrsHealthCheck = settings.fsrsHealthCheck
            request.fsrsReschedule = fsrsReschedule
            try await store.modify(.updateDeckConfigs(request))
            saveError = nil
            return true
        } catch {
            saveError = error.message
            return false
        }
    }

    /// Forgets the last save error once the learner has seen it.
    public func dismissSaveError() {
        saveError = nil
    }

    /// The selected preset as it is sent. If the learner did not edit it, it
    /// is sent exactly as stored: `GetDeckConfigsForUpdate` fills empty FSRS
    /// 6 parameters from older ones for display, which would otherwise be
    /// written back.
    private func configForSaving(_ entry: PresetEntry) async throws(CoreError) -> Anki_DeckConfig_DeckConfig {
        guard let saved = entry.saved, entry.config == saved else { return entry.config }
        return try await store.core.getDeckConfig(.with { $0.dcid = saved.id })
    }

    /// The deck's own limits as the core expects them back. A "today only"
    /// limit set on an earlier day is kept by sending none, as Anki's own
    /// deck options do; sending it would make it apply today again.
    private static func limitsForSaving(
        _ limits: Anki_DeckConfig_DeckConfigsForUpdate.CurrentDeck.Limits
    ) -> Anki_DeckConfig_DeckConfigsForUpdate.CurrentDeck.Limits {
        var limits = limits
        if !limits.reviewTodayActive { limits.clearReviewToday() }
        if !limits.newTodayActive { limits.clearNewToday() }
        return limits
    }

    // MARK: Helpers for sections

    var selectedIndex: Int? {
        entries.firstIndex { $0.id == selectedID }
    }

    private var selectedEntry: PresetEntry? {
        selectedIndex.map { entries[$0] }
    }

    /// The options of the preset this deck uses, edited in place.
    var selectedConfig: Anki_DeckConfig_DeckConfig.Config {
        get { selectedEntry?.config.config ?? Anki_DeckConfig_DeckConfig.Config() }
        set {
            guard let index = selectedIndex, entries[index].config.config != newValue else { return }
            entries[index].config.config = newValue
        }
    }

    private func insertUnsaved(_ config: Anki_DeckConfig_DeckConfig) {
        var config = config
        config.name = Self.cleanName(config.name)
        let id = PresetID(rawValue: nextUnsavedID)
        nextUnsavedID -= 1
        entries.append(PresetEntry(id: id, config: config, saved: nil, savedDeckCount: 0))
        selectedID = id
    }

    /// How many decks will use a preset once saved: the stored count, moved
    /// by this deck's choice and by decks whose preset is deleted, which then
    /// use the preset this deck uses.
    private func deckCount(of entry: PresetEntry) -> Int {
        var count = entry.savedDeckCount
        if entry.id == loadedSelectedID { count -= 1 }
        if entry.id == selectedID {
            count += 1
            count += loadedSettings.allConfig
                .filter { removedConfigIDs.contains($0.config.id) }
                .map { Int($0.useCount) - ($0.config.id == loadedSelectedID.rawValue ? 1 : 0) }
                .reduce(0, +)
        }
        return count
    }

    private static func cleanName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A preset being edited: the core's message, changed in place, beside the
/// copy the core sent (nil for a preset added on the screen).
struct PresetEntry {
    let id: PresetID
    var config: Anki_DeckConfig_DeckConfig
    let saved: Anki_DeckConfig_DeckConfig?
    let savedDeckCount: Int
}
