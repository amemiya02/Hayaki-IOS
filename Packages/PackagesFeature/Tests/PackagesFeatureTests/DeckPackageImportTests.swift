import AnkiProto
import CollectionStore
import CollectionTesting
import Foundation
import PackagesFeature
import Testing

@MainActor
@Suite("Importing a deck package", .timeLimit(.minutes(2)))
struct DeckPackageImportTests {
    @Test("Opening a deck package offers the core's merge choices before anything changes")
    func offersMergeChoices() async throws {
        try await withTemporaryCollection { store in
            let backups = try TemporaryFolder()
            let model = PackageImportModel(store: store, backupFolder: backups.url)

            await model.open(FixturePackage.basicDeck.url)

            guard case .choosingMergeOptions(let package) = model.step else {
                Issue.record("expected merge choices, got \(model.step)")
                return
            }
            #expect(package.kind == .deckPackage)
            #expect(package.name == "basic.apkg")
            // A new collection starts from the core's own defaults: no learning
            // progress, notes updated only when the incoming one is newer.
            #expect(model.mergeOptions.includeLearningProgress == false)
            #expect(model.mergeOptions.includeDeckPresets == false)
            #expect(model.mergeOptions.mergeNotetypes == false)
            #expect(model.mergeOptions.updateNotes == .ifNewer)
            #expect(model.mergeOptions.updateNotetypes == .ifNewer)
            #expect(try await store.contents().notes == 0)
        }
    }

    @Test("A deck package with its learning progress brings notes, cards, scheduling, review history and media")
    func importsWithLearningProgress() async throws {
        try await withTemporaryCollection { store in
            let backups = try TemporaryFolder()
            let model = PackageImportModel(store: store, backupFolder: backups.url)
            await model.open(FixturePackage.basicDeck.url)
            model.mergeOptions.includeLearningProgress = true

            await model.startImport()

            #expect(try await store.contents() == FixturePackage.basicDeck.contents)
            guard case .finished(.merged(let result)) = model.step else {
                Issue.record("expected a merge summary, got \(model.step)")
                return
            }
            #expect(result.added.sorted() == ["adiós", "el sol", "gracias", "por favor"])
            #expect(result.updated.isEmpty)
            #expect(result.skipped.isEmpty)
            // The image arrives byte for byte.
            let image = try Data(contentsOf: store.location.mediaFolder.appendingPathComponent("sol.png"))
            #expect(image.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        }
    }

    @Test("Without learning progress, the cards arrive as new cards with no review history")
    func importsWithoutLearningProgress() async throws {
        try await withTemporaryCollection { store in
            let backups = try TemporaryFolder()
            let model = PackageImportModel(store: store, backupFolder: backups.url)
            await model.open(FixturePackage.clozeDeck.url)
            model.mergeOptions.includeLearningProgress = false

            await model.startImport()

            let contents = try await store.contents()
            #expect(contents.notes == 2)
            #expect(contents.cards == 3)
            #expect(contents.studiedCards == 0)
            #expect(contents.reviews == 0)
            #expect(try await store.deckNames().contains("Geography"))
        }
    }

    @Test("Typed-answer notes arrive with their note type")
    func importsTypedAnswerNotes() async throws {
        try await withTemporaryCollection { store in
            let backups = try TemporaryFolder()
            let model = PackageImportModel(store: store, backupFolder: backups.url)
            await model.open(FixturePackage.typedAnswerDeck.url)
            model.mergeOptions.includeLearningProgress = true

            await model.startImport()

            #expect(try await store.contents() == FixturePackage.typedAnswerDeck.contents)
            // The package brings its own copy of the note type; the core keeps
            // it apart from the collection's stock one by adding a suffix.
            let typed = try await store.noteIDs(matching: "\"note:Basic (type in the answer)*\"")
            #expect(typed.count == 2)
        }
    }

    @Test("The collection signals the import, so the deck list and other screens refresh")
    func signalsChanges() async throws {
        try await withTemporaryCollection { store in
            let backups = try TemporaryFolder()
            let model = PackageImportModel(store: store, backupFolder: backups.url)
            let changes = store.changes()
            await model.open(FixturePackage.basicDeck.url)

            await model.startImport()

            var heard = changes.makeAsyncIterator()
            let change = try #require(await heard.next())
            #expect(change.isSuperset(of: [.deck, .card, .note]))
        }
    }

    @Test("A file that is not an Anki package is refused without changing anything")
    func refusesOtherFiles() async throws {
        try await withTemporaryCollection { store in
            let folder = try TemporaryFolder()
            let notes = folder.url.appendingPathComponent("notes.txt")
            try Data("hello".utf8).write(to: notes)
            let model = PackageImportModel(store: store, backupFolder: folder.url)

            await model.open(notes)

            guard case .failed = model.step else {
                Issue.record("expected a refusal, got \(model.step)")
                return
            }
            #expect(try await store.contents().notes == 0)
        }
    }
}
