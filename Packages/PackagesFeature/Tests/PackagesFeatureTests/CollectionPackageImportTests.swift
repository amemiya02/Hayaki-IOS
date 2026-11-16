import AnkiCore
import AnkiProto
import CollectionStore
import CollectionTesting
import Foundation
import PackagesFeature
import Testing

@MainActor
@Suite("Importing a collection package", .timeLimit(.minutes(3)))
struct CollectionPackageImportTests {
    @Test("Opening a collection package asks the learner to confirm before anything changes")
    func asksToConfirm() async throws {
        try await withTemporaryCollection { store in
            try await store.addDeck(named: "My Own Deck")
            let backups = try TemporaryFolder()
            let model = PackageImportModel(store: store, backupFolder: backups.url)

            await model.open(FixturePackage.collection.url)

            guard case .confirmingReplace(let package) = model.step else {
                Issue.record("expected a confirmation, got \(model.step)")
                return
            }
            #expect(package.kind == .collectionPackage)
            #expect(package.name == "collection.colpkg")
            #expect(try await store.deckNames() == ["Default", "My Own Deck"])
            #expect(try backups.backupFiles().isEmpty)
        }
    }

    @Test("Declining leaves the collection as it was, with no backup")
    func declining() async throws {
        try await withTemporaryCollection { store in
            try await store.addDeck(named: "My Own Deck")
            let backups = try TemporaryFolder()
            let model = PackageImportModel(store: store, backupFolder: backups.url)
            await model.open(FixturePackage.collection.url)

            model.cancel()

            #expect(model.step == .idle)
            #expect(try await store.deckNames() == ["Default", "My Own Deck"])
            #expect(try backups.backupFiles().isEmpty)
        }
    }

    @Test("Confirming backs up the current collection, then replaces it with the package's, review history and media included")
    func replacesAfterBackup() async throws {
        try await withTemporaryCollection { store in
            let mine = try await store.addDeck(named: "My Own Deck")
            try await store.addBasicNotes(count: 3, toDeck: mine)
            let backups = try TemporaryFolder()
            let model = PackageImportModel(store: store, backupFolder: backups.url)
            let changes = store.changes()
            await model.open(FixturePackage.collection.url)

            await model.startImport()

            #expect(try await store.contents() == FixturePackage.collection.contents)
            #expect(model.step == .finished(.replaced(ReplaceResult(decks: 4, notes: 8, cards: 9, backupMade: true))))
            var heard = changes.makeAsyncIterator()
            #expect(await heard.next() == .everything)

            // The backup holds the collection as it was before.
            let backup = try #require(try backups.backupFiles().first)
            try await withTemporaryCollection { restored in
                try await restored.replace { core, location in
                    try await core.importCollectionPackage(.with {
                        $0.colPath = location.collectionFile.path
                        $0.backupPath = backup.path
                        $0.mediaFolder = location.mediaFolder.path
                        $0.mediaDb = location.mediaDatabase.path
                    })
                }
                #expect(try await restored.deckNames() == ["Default", "My Own Deck"])
                #expect(try await restored.contents().notes == 3)
            }
        }
    }

    @Test("A damaged package fails and leaves the previous collection intact")
    func damagedPackage() async throws {
        try await withTemporaryCollection { store in
            let mine = try await store.addDeck(named: "My Own Deck")
            try await store.addBasicNotes(count: 3, toDeck: mine)
            let folder = try TemporaryFolder()
            let damaged = folder.url.appendingPathComponent("damaged.colpkg")
            try Data(repeating: 7, count: 4096).write(to: damaged)
            let model = PackageImportModel(store: store, backupFolder: folder.url.appendingPathComponent("Backups"))
            await model.open(damaged)

            await model.startImport()

            guard case .failed = model.step else {
                Issue.record("expected a failure, got \(model.step)")
                return
            }
            #expect(try await store.deckNames() == ["Default", "My Own Deck"])
            #expect(try await store.contents().notes == 3)
        }
    }

    /// The core checks for a cancel only at its progress checkpoints; once
    /// past the last one it finishes. So a cancel either stops the import, or
    /// comes too late and the import completes. Which one depends on timing;
    /// a half-imported collection must never result.
    @Test("Cancelling a running import leaves the previous collection intact, or lets it finish in full, never partly")
    func cancelling() async throws {
        let large = try await LargePackages.make()
        try await withTemporaryCollection { store in
            let mine = try await store.addDeck(named: "My Own Deck")
            try await store.addBasicNotes(count: 3, toDeck: mine)
            let backups = try TemporaryFolder()
            let model = PackageImportModel(store: store, backupFolder: backups.url)
            await model.open(large.collectionPackage)

            let importing = Task { await model.startImport() }
            try await eventually(timeout: .seconds(30), "the import started") { model.isImporting }
            model.cancel()
            await importing.value

            switch model.step {
            case .cancelled:
                print("Collection package cancel: the import stopped")
                #expect(try await store.deckNames() == ["Default", "My Own Deck"])
                #expect(try await store.contents().notes == 3)
            case .finished(.replaced(let result)):
                print("Collection package cancel: came too late, the import finished")
                #expect(result.notes == LargePackages.noteCount)
                #expect(try await store.deckNames() == ["Default", "Large"])
                #expect(try await store.contents().notes == LargePackages.noteCount)
            default:
                Issue.record("expected the import cancelled or finished, got \(model.step)")
            }
        }
    }
}

@MainActor
@Suite("Cancelling a deck package import", .timeLimit(.minutes(3)))
struct DeckPackageCancelTests {
    /// The core checks for a cancel only at its progress checkpoints (reading
    /// the package, then every few notes); adding the cards and review history
    /// has none, so a cancel that arrives then is not seen and the import
    /// finishes. Its transaction makes it all or nothing either way.
    @Test("Cancelling a running import merges nothing, or lets it finish in full, never partly")
    func cancelling() async throws {
        let large = try await LargePackages.make()
        try await withTemporaryCollection { store in
            let backups = try TemporaryFolder()
            let model = PackageImportModel(store: store, backupFolder: backups.url)
            await model.open(large.deckPackage)

            let importing = Task { await model.startImport() }
            try await eventually(timeout: .seconds(60), "the import started") { model.isImporting }
            model.cancel()
            await importing.value

            switch model.step {
            case .cancelled:
                print("Deck package cancel: the import stopped")
                #expect(try await store.contents().notes == 0)
                #expect(try await store.contents().cards == 0)
            case .finished(.merged(let result)):
                print("Deck package cancel: came too late, the import finished")
                #expect(result.added.count == LargePackages.noteCount)
                #expect(try await store.contents().notes == LargePackages.noteCount)
                #expect(try await store.contents().cards == LargePackages.noteCount)
            default:
                Issue.record("expected the import cancelled or finished, got \(model.step)")
            }
        }
    }
}

extension TemporaryFolder {
    func backupFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "colpkg" }
    }
}

/// Packages large enough that an import runs long enough to be cancelled.
struct LargePackages: ~Copyable {
    let folder: TemporaryFolder
    var collectionPackage: URL { folder.url.appendingPathComponent("large.colpkg") }
    var deckPackage: URL { folder.url.appendingPathComponent("large.apkg") }

    static let noteCount = 20_000

    static func make(notes: Int = noteCount) async throws -> LargePackages {
        let packages = LargePackages(folder: try TemporaryFolder())
        let store = try await CollectionStore.open(
            at: CollectionLocation(folder: packages.folder.url.appendingPathComponent("Collection")),
            core: CoreClient(language: "en")
        )
        let deck = try await store.addDeck(named: "Large")
        try await store.addBasicNotes(count: notes, toDeck: deck)
        _ = try await store.core.exportAnkiPackage(.with {
            $0.outPath = packages.deckPackage.path
            $0.limit.deckID = deck
        })
        try await store.core.exportCollectionPackage(.with {
            $0.outPath = packages.collectionPackage.path
            $0.includeMedia = true
        })
        return packages
    }
}
