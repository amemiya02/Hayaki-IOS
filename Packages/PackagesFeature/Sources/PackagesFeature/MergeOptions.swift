import AnkiProto

/// How a deck package is merged into the collection: the core's own import
/// options, as Anki's import screen offers them.
public struct MergeOptions: Sendable, Equatable {
    /// When a note already in the collection is replaced by the package's copy.
    public enum UpdateCondition: Sendable, Equatable, CaseIterable {
        /// Only if the package's copy was changed more recently.
        case ifNewer
        /// Whenever the two differ.
        case always
        /// Never; the collection's copy is kept.
        case never
    }

    /// Bring the package's scheduling and review history for cards that are
    /// new to the collection. Without it, those cards arrive as new cards.
    public var includeLearningProgress: Bool
    /// Bring the deck presets of the package's decks.
    public var includeDeckPresets: Bool
    /// Merge a note type that differs from the collection's copy into it,
    /// instead of keeping both.
    public var mergeNotetypes: Bool
    public var updateNotes: UpdateCondition
    public var updateNotetypes: UpdateCondition

    public init(
        includeLearningProgress: Bool = false,
        includeDeckPresets: Bool = false,
        mergeNotetypes: Bool = false,
        updateNotes: UpdateCondition = .ifNewer,
        updateNotetypes: UpdateCondition = .ifNewer
    ) {
        self.includeLearningProgress = includeLearningProgress
        self.includeDeckPresets = includeDeckPresets
        self.mergeNotetypes = mergeNotetypes
        self.updateNotes = updateNotes
        self.updateNotetypes = updateNotetypes
    }

    /// The choices the collection remembers from the last import, which the
    /// core returns as its presets.
    init(_ presets: Anki_ImportExport_ImportAnkiPackageOptions) {
        self.init(
            includeLearningProgress: presets.withScheduling,
            includeDeckPresets: presets.withDeckConfigs,
            mergeNotetypes: presets.mergeNotetypes,
            updateNotes: UpdateCondition(presets.updateNotes),
            updateNotetypes: UpdateCondition(presets.updateNotetypes)
        )
    }

    var request: Anki_ImportExport_ImportAnkiPackageOptions {
        .with {
            $0.withScheduling = includeLearningProgress
            $0.withDeckConfigs = includeDeckPresets
            $0.mergeNotetypes = mergeNotetypes
            $0.updateNotes = updateNotes.proto
            $0.updateNotetypes = updateNotetypes.proto
        }
    }
}

private extension MergeOptions.UpdateCondition {
    init(_ condition: Anki_ImportExport_ImportAnkiPackageUpdateCondition) {
        switch condition {
        case .always: self = .always
        case .never: self = .never
        case .ifNewer, .UNRECOGNIZED: self = .ifNewer
        }
    }

    var proto: Anki_ImportExport_ImportAnkiPackageUpdateCondition {
        switch self {
        case .ifNewer: .ifNewer
        case .always: .always
        case .never: .never
        }
    }
}
