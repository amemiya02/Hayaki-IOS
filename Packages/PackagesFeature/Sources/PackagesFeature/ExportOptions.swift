import AnkiProto
import Foundation

/// The choices desktop Anki's export screen offers for its two package
/// kinds, with its defaults.
public struct ExportOptions: Sendable, Equatable {
    /// Deck packages only: bring the cards' scheduling and review history.
    /// Without it the cards arrive as new cards. A collection package always
    /// carries scheduling.
    public var includeScheduling: Bool
    /// Deck packages only: bring the presets the decks use.
    public var includeDeckPresets: Bool
    /// Bring the sounds and images the notes use (a deck package), or the
    /// whole media folder (a collection package).
    public var includeMedia: Bool
    /// Write the older package format, which Anki versions before 2.1.50 can
    /// read too. Such files are larger and slower to write.
    public var supportOlderVersions: Bool

    public init(
        includeScheduling: Bool = true,
        includeDeckPresets: Bool = false,
        includeMedia: Bool = true,
        supportOlderVersions: Bool = false
    ) {
        self.includeScheduling = includeScheduling
        self.includeDeckPresets = includeDeckPresets
        self.includeMedia = includeMedia
        self.supportOlderVersions = supportOlderVersions
    }
}

/// A deck the learner can choose to export.
public struct ExportableDeck: Sendable, Equatable, Identifiable {
    public let id: Int64
    /// The full name, such as "Languages::Spanish".
    public let fullName: String

    /// The last part of the name, such as "Spanish".
    public var name: String {
        fullName.components(separatedBy: "::").last ?? fullName
    }

    /// How deep the deck is nested: 0 for a top-level deck.
    public var depth: Int {
        fullName.components(separatedBy: "::").count - 1
    }
}

/// A package an export wrote.
public struct ExportedPackage: Sendable, Equatable {
    public let kind: PackageKind
    /// Where the file is, in the export folder.
    public let url: URL
    /// The size of the file, in bytes.
    public let byteCount: Int64
    /// How many notes a deck package holds; nil for a collection package.
    public let noteCount: Int?

    /// The file's name, such as "Spanish.apkg".
    public var name: String { url.lastPathComponent }
}

/// Specific cards or notes to export from Browse.
public enum ExportSelection: Equatable, Sendable {
    case cards([Int64])
    case notes([Int64])

    var count: Int {
        switch self {
        case .cards(let ids), .notes(let ids): ids.count
        }
    }

    var limit: Anki_ImportExport_ExportLimit {
        .with {
            switch self {
            case .cards(let ids): $0.cardIds = .with { $0.cids = ids }
            case .notes(let ids): $0.noteIds = .with { $0.noteIds = ids }
            }
        }
    }
}
