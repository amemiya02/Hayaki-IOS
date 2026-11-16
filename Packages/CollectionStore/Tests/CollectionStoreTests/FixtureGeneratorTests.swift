import AnkiCore
import AnkiProto
import CollectionStore
import CollectionTesting
import Foundation
import Testing

/// The fixture packages in `Sources/CollectionTesting/Fixtures` are written by
/// `FixtureGenerator` below through the pinned core (Anki 26.09.4's own export
/// code). These tests check that the generator still produces what
/// `FixturePackage.contents` describes, and that the committed files do.
///
/// To regenerate the committed files:
///
///     HAYAKI_WRITE_FIXTURES=1 scripts/test.sh CollectionStore
@Suite("Fixture packages", .timeLimit(.minutes(2)))
struct FixtureGeneratorTests {
    @Test("The generator writes packages holding what each fixture is described to hold")
    func generatedPackages() async throws {
        let scratch = try TemporaryFolder()
        let output = FixtureGenerator.writesCommittedFixtures ? FixtureGenerator.committedFolder : scratch.url
        try await FixtureGenerator.writePackages(to: output)

        for fixture in FixturePackage.allCases {
            let package = output.appendingPathComponent(fixture.fileName)
            try await withTemporaryCollection { store in
                try await store.importPackage(at: package, isCollectionPackage: fixture.isCollectionPackage)
                #expect(try await store.contents() == fixture.contents, "\(fixture.fileName)")
            }
        }
    }

    @Test("Each committed fixture package holds what it is described to hold", arguments: FixturePackage.allCases)
    func committedPackage(_ fixture: FixturePackage) async throws {
        try await withTemporaryCollection { store in
            try await store.importFixture(fixture)
            #expect(try await store.contents() == fixture.contents)
            // Every note has its own GUID, which imports match notes by.
            var guids: Set<String> = []
            for noteID in try await store.noteIDs() {
                guids.insert(try await store.core.getNote(.with { $0.nid = noteID }).guid)
            }
            #expect(guids.count == fixture.contents.notes)
        }
    }
}

private extension CollectionStore {
    func importPackage(at package: URL, isCollectionPackage: Bool) async throws {
        if isCollectionPackage {
            try await replace { core, location in
                try await core.importCollectionPackage(.with {
                    $0.colPath = location.collectionFile.path
                    $0.backupPath = package.path
                    $0.mediaFolder = location.mediaFolder.path
                    $0.mediaDb = location.mediaDatabase.path
                })
            }
        } else {
            try await modify(.importAnkiPackage(.with {
                $0.packagePath = package.path
                $0.options.withScheduling = true
                $0.options.withDeckConfigs = true
            }))
        }
    }
}

/// Builds the fixture collection through the core and exports it as one
/// collection package and three deck packages. See `FixturePackage` for what
/// they hold.
enum FixtureGenerator {
    static var writesCommittedFixtures: Bool {
        ProcessInfo.processInfo.environment["HAYAKI_WRITE_FIXTURES"] == "1"
    }

    /// `Packages/CollectionStore/Sources/CollectionTesting/Fixtures`.
    static var committedFolder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Sources/CollectionTesting/Fixtures")
            .standardizedFileURL
    }

    /// The media the notes use, kept beside this file.
    private static func media(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("FixtureMedia/\(name)"))
    }

    static func writePackages(to folder: URL) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let work = try TemporaryFolder()
        let store = try await CollectionStore.open(
            at: CollectionLocation(folder: work.url.appendingPathComponent("Collection")),
            core: CoreClient(language: "en")
        )

        let image = try await store.addMediaFile(named: "sol.png", data: try media("sol.png"))
        let sound = try await store.addMediaFile(named: "adios.m4a", data: try media("adios.m4a"))

        let spanish = try await store.addDeck(named: "Languages::Spanish")
        try await store.addNotes(ofType: "Basic", fields: [
            ["el sol", "the sun<br><img src=\"\(image)\">"],
            ["adiós", "goodbye [sound:\(sound)]"],
            ["gracias", "thank you"],
            ["por favor", "please"],
        ], toDeck: spanish)

        let geography = try await store.addDeck(named: "Geography")
        try await store.addNotes(ofType: "Cloze", fields: [
            ["{{c1::Paris}} is the capital of {{c2::France}}.", ""],
            ["The area of a circle of radius r is {{c1::\\(\\pi r^2\\)}}.", "MathJax"],
        ], toDeck: geography)

        let vocabulary = try await store.addDeck(named: "Vocabulary")
        try await store.addNotes(ofType: "Basic (type in the answer)", fields: [
            ["Capital of Japan", "Tokyo"],
            ["Largest planet", "Jupiter"],
        ], toDeck: vocabulary)

        // Review history: Easy graduates a new card to review; Good leaves it
        // in learning.
        try await store.answerNextCard(inDeck: spanish, rating: .easy)
        try await store.answerNextCard(inDeck: spanish, rating: .good)
        try await store.answerNextCard(inDeck: geography, rating: .easy)
        try await store.answerNextCard(inDeck: vocabulary, rating: .good)

        for (fixture, deckID) in [
            (FixturePackage.basicDeck, spanish), (.clozeDeck, geography), (.typedAnswerDeck, vocabulary),
        ] {
            let out = folder.appendingPathComponent(fixture.fileName)
            try? FileManager.default.removeItem(at: out)
            // Anki's "Export" with scheduling, deck presets and media included.
            _ = try await store.core.exportAnkiPackage(.with {
                $0.outPath = out.path
                $0.options.withScheduling = true
                $0.options.withDeckConfigs = true
                $0.options.withMedia = true
                $0.options.legacy = false
                $0.limit.deckID = deckID
            })
        }

        let collection = folder.appendingPathComponent(FixturePackage.collection.fileName)
        try? FileManager.default.removeItem(at: collection)
        // Exporting a collection package closes the collection.
        try await store.core.exportCollectionPackage(.with {
            $0.outPath = collection.path
            $0.includeMedia = true
            $0.legacy = false
        })
    }
}
