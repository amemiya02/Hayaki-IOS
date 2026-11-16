import AnkiCore
import AnkiProto
import CollectionStore
import CollectionTesting
import Foundation
import PackagesFeature
import Testing

@MainActor
@Suite("Exporting packages: choices, progress and cancelling", .timeLimit(.minutes(5)))
struct ExportProgressTests {
    @Test("The whole collection is the starting choice, with Anki's defaults")
    func defaults() async throws {
        try await withTemporaryCollection { store in
            let exports = try TemporaryFolder()
            let model = PackageExportModel(store: store, exportFolder: exports.url)

            #expect(model.kind == .collectionPackage)
            #expect(model.options == ExportOptions(
                includeScheduling: true, includeDeckPresets: false, includeMedia: true, supportOlderVersions: false
            ))
            #expect(model.canExport)
        }
    }

    @Test("A deck package needs at least one chosen deck")
    func deckPackageNeedsDecks() async throws {
        try await withTemporaryCollection { store in
            let exports = try TemporaryFolder()
            let model = PackageExportModel(store: store, exportFolder: exports.url)
            model.kind = .deckPackage

            #expect(!model.canExport)
            await model.export()

            #expect(model.step == .choosing)
            #expect(try FileManager.default.contentsOfDirectory(atPath: exports.url.path).isEmpty)
        }
    }

    @Test("The decks to choose from are listed parents first, filtered decks included, the empty Default left out")
    func listsDecks() async throws {
        try await withTemporaryCollection { store in
            try await store.importFixture(.collection)
            try await store.addFilteredDeck(named: "Cram", search: "deck:Geography")
            let exports = try TemporaryFolder()
            let model = PackageExportModel(store: store, exportFolder: exports.url)

            await model.loadDecks()

            #expect(model.decks.map(\.fullName) == ["Cram", "Geography", "Languages", "Languages::Spanish", "Vocabulary"])
            #expect(model.decks.map(\.name) == ["Cram", "Geography", "Languages", "Spanish", "Vocabulary"])
            #expect(model.decks.map(\.depth) == [0, 0, 0, 1, 0])
        }
    }

    @Test("While the core writes the package, its progress shows")
    func showsProgress() async throws {
        try await withTemporaryCollection { store in
            try await store.addLargeContent()
            let exports = try TemporaryFolder()
            let model = PackageExportModel(store: store, exportFolder: exports.url)

            let exporting = Task { await model.export() }
            // The core reports a new stage about every tenth of a second.
            var seen: [String] = []
            try await eventually(timeout: .seconds(60), "the export started") { model.isExporting }
            while model.isExporting {
                if case .exporting(let progress?) = model.step, seen.last != progress {
                    seen.append(progress)
                }
                try await Task.sleep(for: .milliseconds(2))
            }
            await exporting.value

            #expect(model.exportedPackage != nil)
            #expect(!seen.isEmpty)
            print("Export progress seen: \(seen)")
        }
    }

    /// The core checks for a cancel at its progress checkpoints (every few
    /// media files while it writes them), so a cancel normally stops it; one
    /// that arrives after the last checkpoint is too late and the export
    /// finishes. Either way the collection stays as it was and no half
    /// written file is left.
    @Test("Cancelling stops the export, leaves no file and the collection open and unchanged")
    func cancelling() async throws {
        try await withTemporaryCollection { store in
            try await store.addLargeContent()
            let before = try await store.contents()
            let exports = try TemporaryFolder()
            let model = PackageExportModel(store: store, exportFolder: exports.url)

            let exporting = Task { await model.export() }
            try await eventually(timeout: .seconds(60), "the export started") { model.isExporting }
            model.cancel()
            await exporting.value

            switch model.step {
            case .cancelled:
                print("Collection package export cancel: the export stopped")
                #expect(try FileManager.default.contentsOfDirectory(atPath: exports.url.path).isEmpty)
            case .finished(let package):
                print("Collection package export cancel: came too late, the export finished")
                #expect(try FileManager.default.contentsOfDirectory(atPath: exports.url.path) == [package.name])
            default:
                Issue.record("expected the export cancelled or finished, got \(model.step)")
            }
            #expect(try await store.contents() == before)

            // The learner can export again.
            model.startOver()
            #expect(model.step == .choosing)
            await model.export()
            #expect(model.exportedPackage != nil)
        }
    }

    @Test("Cancelling a deck package export stops it, or lets it finish, never leaving a half-written file")
    func cancellingDeckPackage() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addLargeContent()
            let exports = try TemporaryFolder()
            let model = PackageExportModel(store: store, exportFolder: exports.url, decks: [deck])

            let exporting = Task { await model.export() }
            try await eventually(timeout: .seconds(60), "the export started") { model.isExporting }
            model.cancel()
            await exporting.value

            switch model.step {
            case .cancelled:
                print("Deck package export cancel: the export stopped")
                #expect(try FileManager.default.contentsOfDirectory(atPath: exports.url.path).isEmpty)
            case .finished(let package):
                print("Deck package export cancel: came too late, the export finished")
                #expect(package.noteCount == 20_000)
            default:
                Issue.record("expected the export cancelled or finished, got \(model.step)")
            }
        }
    }

    @Test("Exporting tells everything showing the collection to reload, since the core closes and reopens it")
    func signalsReopen() async throws {
        try await withTemporaryCollection { store in
            try await store.importFixture(.collection)
            let changes = store.changes()
            let exports = try TemporaryFolder()
            let model = PackageExportModel(store: store, exportFolder: exports.url)

            await model.export()

            var heard = changes.makeAsyncIterator()
            #expect(await heard.next() == .everything)
        }
    }
}

extension CollectionStore {
    /// A deck of 20,000 notes and 1,500 media files, so that exporting takes
    /// long enough to see progress and cancel. Returns the deck's id.
    @discardableResult
    func addLargeContent() async throws -> Int64 {
        let deck = try await addDeck(named: "Large")
        try await addNotes(
            ofType: "Basic",
            fields: (0..<20_000).map { ["Question \($0) <img src=\"image\($0 % 1_500).png\">", "Answer \($0)"] },
            toDeck: deck
        )
        // Random bytes do not compress, so writing each file takes real work.
        var random = SystemRandomNumberGenerator()
        let noise = (0..<(16_384 / 8)).flatMap { _ in withUnsafeBytes(of: random.next()) { Array($0) } }
        for index in 0..<1_500 {
            let bytes = withUnsafeBytes(of: index) { Array($0) } + noise
            try Data(bytes).write(to: location.mediaFolder.appendingPathComponent("image\(index).png"))
        }
        return deck
    }
}
