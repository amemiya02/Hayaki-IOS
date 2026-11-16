import Foundation

/// Real Anki package files for tests: a collection package and three deck
/// packages, written by the export code of Anki 26.09.4, the version of the
/// core Hayaki embeds.
///
/// They are produced by the same pinned core, not by a desktop Anki install:
/// `FixtureGeneratorTests` in `Packages/CollectionStore/Tests` builds a small
/// collection through the core and exports it. Regenerate them with
///
///     HAYAKI_WRITE_FIXTURES=1 scripts/test.sh CollectionStore
///
/// and update `contents` below if what they hold changes. Note ids, card ids
/// and dates differ on every regeneration; what the packages hold does not.
///
/// The collection holds three decks of the three common note types:
///
/// - `Languages::Spanish`: 4 Basic notes, 4 cards. "el sol" shows the image
///   `sol.png`; "adiós" plays `adios.m4a`. One card answered Easy (now a
///   review card), one answered Good (now learning).
/// - `Geography`: 2 Cloze notes, 3 cards; one note has MathJax. One card
///   answered Easy.
/// - `Vocabulary`: 2 "Basic (type in the answer)" notes, 2 cards. One card
///   answered Good.
///
/// Each deck package holds one of those decks, exported with scheduling and
/// media, so its notes are the same notes (same GUIDs) as in the collection
/// package.
public enum FixturePackage: String, CaseIterable, Sendable {
    /// The whole collection: `collection.colpkg`.
    case collection = "collection.colpkg"
    /// `Languages::Spanish`, Basic notes with an image and audio: `basic.apkg`.
    case basicDeck = "basic.apkg"
    /// `Geography`, Cloze notes: `cloze.apkg`.
    case clozeDeck = "cloze.apkg"
    /// `Vocabulary`, typed-answer notes: `typed-answer.apkg`.
    case typedAnswerDeck = "typed-answer.apkg"

    /// The file name, with its extension.
    public var fileName: String { rawValue }

    /// The package file, inside this library's resources. Copy it before
    /// handing it to anything that might move or change it.
    public var url: URL {
        guard let url = Bundle.module.url(forResource: fileName, withExtension: nil, subdirectory: "Fixtures") else {
            fatalError("Fixture \(fileName) is missing from CollectionTesting's resources")
        }
        return url
    }

    /// Whether this is a collection package, which replaces the collection,
    /// rather than a deck package, which merges into it.
    public var isCollectionPackage: Bool { self == .collection }

    /// What the package holds.
    public var contents: FixtureContents {
        switch self {
        case .collection:
            FixtureContents(
                decks: ["Geography", "Languages", "Languages::Spanish", "Vocabulary"],
                notes: 8, cards: 9, studiedCards: 4, reviews: 4,
                mediaFiles: ["adios.m4a", "sol.png"]
            )
        case .basicDeck:
            FixtureContents(
                decks: ["Languages", "Languages::Spanish"],
                notes: 4, cards: 4, studiedCards: 2, reviews: 2,
                mediaFiles: ["adios.m4a", "sol.png"]
            )
        case .clozeDeck:
            FixtureContents(
                decks: ["Geography"],
                notes: 2, cards: 3, studiedCards: 1, reviews: 1,
                mediaFiles: []
            )
        case .typedAnswerDeck:
            FixtureContents(
                decks: ["Vocabulary"],
                notes: 2, cards: 2, studiedCards: 1, reviews: 1,
                mediaFiles: []
            )
        }
    }
}

/// What a fixture package holds.
public struct FixtureContents: Sendable, Equatable {
    /// Full names of the decks that hold its cards and their parents, sorted
    /// (the collection's empty Default deck is not listed).
    public let decks: [String]
    public let notes: Int
    public let cards: Int
    /// Cards that have been studied at least once, so are no longer new.
    public let studiedCards: Int
    /// Entries of review history.
    public let reviews: Int
    /// Media file names, sorted.
    public let mediaFiles: [String]
}
