import AnkiCore
import AnkiProto
import CollectionStore
import Foundation

/// Setup and inspection for tests that start from, or check, real package
/// contents.
extension CollectionStore {
    /// Brings a fixture package into this collection through the core, as a
    /// learner importing it would: a collection package replaces the
    /// collection, a deck package is merged in with its scheduling and deck
    /// options.
    public func importFixture(_ fixture: FixturePackage) async throws {
        let copy = try TemporaryFolder()
        let package = copy.url.appendingPathComponent(fixture.fileName)
        try FileManager.default.copyItem(at: fixture.url, to: package)
        if fixture.isCollectionPackage {
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

    /// The ids of the cards a search in Anki's search syntax finds; every
    /// card for an empty search.
    public func cardIDs(matching search: String = "") async throws -> [Int64] {
        try await core.searchCards(.with { $0.search = search }).ids
    }

    /// The ids of the notes a search in Anki's search syntax finds; every note
    /// for an empty search.
    public func noteIDs(matching search: String = "") async throws -> [Int64] {
        try await core.searchNotes(.with { $0.search = search }).ids
    }

    /// The number of review history entries of the cards a search finds.
    public func reviewCount(matching search: String = "") async throws -> Int {
        var count = 0
        for cardID in try await cardIDs(matching: search) {
            count += try await core.getReviewLogs(.with { $0.cid = cardID }).entries.count
        }
        return count
    }

    /// The names of the files in the collection's media folder, sorted.
    public func mediaFileNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: location.mediaFolder.path)
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }

    /// What the collection holds, in the shape fixture packages are described
    /// in, so a test can compare it with `FixturePackage.contents`. The
    /// Default deck, which every collection has, is left out.
    public func contents() async throws -> FixtureContents {
        FixtureContents(
            decks: try await deckNames().filter { $0 != "Default" },
            notes: try await noteIDs().count,
            cards: try await cardIDs().count,
            studiedCards: try await cardIDs(matching: "-is:new").count,
            reviews: try await reviewCount(),
            mediaFiles: try mediaFileNames()
        )
    }
}
