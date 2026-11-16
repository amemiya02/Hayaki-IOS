import AnkiCore
import AnkiProto
import CollectionStore
import CollectionTesting
import Foundation
import PackagesFeature
import Testing

/// Every export is checked the way it will be used: the file the core wrote is
/// imported into a fresh collection through the core, and that collection
/// must hold the same notes, cards, scheduling, review history and media.
@MainActor
@Suite("Exporting packages: round trips through a fresh collection", .timeLimit(.minutes(3)))
struct ExportRoundTripTests {
    @Test("A collection package carries the whole collection: notes, cards, scheduling, review history and media")
    func collectionPackage() async throws {
        try await withTemporaryCollection { store in
            try await store.importFixture(.collection)
            let original = try await store.snapshot()
            let originalMedia = try store.mediaContents()
            #expect(original.notes.count == 8)
            #expect(original.reviewCount == 4)
            let exports = try TemporaryFolder()
            let model = PackageExportModel(store: store, exportFolder: exports.url)

            await model.export()

            let package = try #require(model.exportedPackage, "expected a finished export, got \(model.step)")
            #expect(package.kind == .collectionPackage)
            #expect(package.url.deletingLastPathComponent().standardizedFileURL == exports.url.standardizedFileURL)
            #expect(package.url.pathExtension == "colpkg")
            // The collection is open again afterwards and unchanged.
            let afterwards = try await store.snapshot()
            #expect(afterwards.differences(from: original) == [])

            try await withTemporaryCollection { fresh in
                try await fresh.importPackage(at: package.url)
                #expect(try await fresh.contents() == FixturePackage.collection.contents)
                let imported = try await fresh.snapshot()
                #expect(imported.differences(from: original) == [])
                #expect(try fresh.mediaContents() == originalMedia)
            }
        }
    }

    @Test("A deck package carries its deck and subdecks with their notes, cards, scheduling, review history and media")
    func deckPackage() async throws {
        try await withTemporaryCollection { store in
            try await store.importFixture(.collection)
            let spanish = try await store.deckID(named: "Languages::Spanish")
            let original = try await store.snapshot(matching: "deck:Languages::Spanish")
            let originalMedia = try store.mediaContents()
            #expect(original.notes.count == 4)
            #expect(original.reviewCount == 2)
            let exports = try TemporaryFolder()
            let model = PackageExportModel(store: store, exportFolder: exports.url, decks: [spanish])
            model.options.includeScheduling = true

            await model.export()

            let package = try #require(model.exportedPackage, "expected a finished export, got \(model.step)")
            #expect(package.kind == .deckPackage)
            #expect(package.name == "Languages__Spanish.apkg")
            #expect(package.noteCount == 4)
            try await withTemporaryCollection { fresh in
                try await fresh.importPackage(at: package.url)
                #expect(try await fresh.contents() == FixturePackage.basicDeck.contents)
                let imported = try await fresh.snapshot()
                #expect(imported.differences(from: original) == [])
                #expect(try fresh.mediaContents() == originalMedia)
            }
        }
    }

    @Test("Several chosen decks go into one deck package")
    func severalDecks() async throws {
        try await withTemporaryCollection { store in
            try await store.importFixture(.collection)
            let chosen: Set = [
                try await store.deckID(named: "Languages::Spanish"),
                try await store.deckID(named: "Geography"),
            ]
            let original = try await store.snapshot(matching: "deck:Languages::Spanish OR deck:Geography")
            #expect(original.notes.count == 6)
            let exports = try TemporaryFolder()
            let model = PackageExportModel(
                store: store, exportFolder: exports.url, decks: chosen,
                now: { Date(timeIntervalSince1970: 1_800_000_000) }
            )
            model.options.includeScheduling = true

            await model.export()

            let package = try #require(model.exportedPackage, "expected a finished export, got \(model.step)")
            #expect(package.noteCount == 6)
            #expect(package.name.hasPrefix("decks-2027-01-1"))
            #expect(package.name.hasSuffix(".apkg"))
            try await withTemporaryCollection { fresh in
                try await fresh.importPackage(at: package.url)
                #expect(try await fresh.deckNames() == ["Default", "Geography", "Languages", "Languages::Spanish"])
                let imported = try await fresh.snapshot()
                #expect(imported.differences(from: original) == [])
            }
        }
    }

    @Test("Without scheduling, a deck package's cards arrive as new cards with no review history")
    func withoutScheduling() async throws {
        try await withTemporaryCollection { store in
            try await store.importFixture(.collection)
            let spanish = try await store.deckID(named: "Languages::Spanish")
            let original = try await store.snapshot(matching: "deck:Languages::Spanish")
            let exports = try TemporaryFolder()
            // Starting from a deck, scheduling is off, as in desktop Anki.
            let model = PackageExportModel(store: store, exportFolder: exports.url, decks: [spanish])
            #expect(model.options.includeScheduling == false)

            await model.export()

            let package = try #require(model.exportedPackage, "expected a finished export, got \(model.step)")
            try await withTemporaryCollection { fresh in
                try await fresh.importPackage(at: package.url)
                let imported = try await fresh.snapshot()
                #expect(imported.notes.map(\.guid) == original.notes.map(\.guid))
                #expect(imported.notes.map(\.fields) == original.notes.map(\.fields))
                #expect(imported.reviewCount == 0)
                #expect(try await fresh.contents().studiedCards == 0)
            }
        }
    }

    @Test("Without media, the package holds no media files")
    func withoutMedia() async throws {
        for kind in [PackageKind.collectionPackage, .deckPackage] {
            try await withTemporaryCollection { store in
                try await store.importFixture(.collection)
                let spanish = try await store.deckID(named: "Languages::Spanish")
                let exports = try TemporaryFolder()
                let model = PackageExportModel(store: store, exportFolder: exports.url, decks: [spanish])
                model.kind = kind
                model.options.includeMedia = false

                await model.export()

                let package = try #require(model.exportedPackage, "expected a finished export, got \(model.step)")
                try await withTemporaryCollection { fresh in
                    try await fresh.importPackage(at: package.url)
                    #expect(try await fresh.contents().notes > 0)
                    #expect(try fresh.mediaFileNames().isEmpty)
                }
            }
        }
    }

    @Test("Supporting older Anki versions writes the older format, which imports the same")
    func olderVersions() async throws {
        for kind in [PackageKind.collectionPackage, .deckPackage] {
            try await withTemporaryCollection { store in
                try await store.importFixture(.collection)
                let spanish = try await store.deckID(named: "Languages::Spanish")
                let search = kind == .collectionPackage ? "" : "deck:Languages::Spanish"
                let original = try await store.snapshot(matching: search)
                let exports = try TemporaryFolder()
                let model = PackageExportModel(store: store, exportFolder: exports.url, decks: [spanish])
                model.kind = kind
                model.options.includeScheduling = true
                model.options.supportOlderVersions = true

                await model.export()

                let package = try #require(model.exportedPackage, "expected a finished export, got \(model.step)")
                // The older format stores the collection as "collection.anki21",
                // uncompressed; the current one as zstd "collection.anki21b".
                let entries = try zipEntryNames(package.url)
                #expect(entries.contains("collection.anki21"))
                #expect(!entries.contains("collection.anki21b"))
                try await withTemporaryCollection { fresh in
                    try await fresh.importPackage(at: package.url)
                    let imported = try await fresh.snapshot()
                    #expect(imported.differences(from: original) == [])
                    #expect(try fresh.mediaFileNames() == ["adios.m4a", "sol.png"])
                }
            }
        }
    }

    @Test("The current format is what desktop Anki 26.09 writes")
    func currentFormat() async throws {
        try await withTemporaryCollection { store in
            try await store.importFixture(.collection)
            let exports = try TemporaryFolder()
            let model = PackageExportModel(store: store, exportFolder: exports.url)

            await model.export()

            let package = try #require(model.exportedPackage, "expected a finished export, got \(model.step)")
            let entries = try zipEntryNames(package.url)
            #expect(entries.contains("meta"))
            #expect(entries.contains("collection.anki21b"))
            #expect(entries.contains("media"))
            // The same layout as the fixture written by the 26.09 core.
            #expect(Set(entries.filter { Int($0) == nil }) == Set(try zipEntryNames(FixturePackage.collection.url).filter { Int($0) == nil }))
        }
    }
}

extension CollectionSnapshot {
    var reviewCount: Int {
        notes.flatMap(\.cards).map(\.reviews.count).reduce(0, +)
    }
}

/// The names of the entries in a zip file, read from its central directory.
func zipEntryNames(_ url: URL) throws -> [String] {
    let data = try Data(contentsOf: url)
    let bytes = [UInt8](data)
    func uint16(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }
    func uint32(_ offset: Int) -> Int { uint16(offset) | uint16(offset + 2) << 16 }
    // End of central directory record: signature 0x06054b50.
    guard let end = stride(from: bytes.count - 22, through: 0, by: -1).first(where: {
        uint32($0) == 0x0605_4b50
    }) else { return [] }
    var offset = uint32(end + 16)
    var names: [String] = []
    for _ in 0..<uint16(end + 10) {
        guard uint32(offset) == 0x0201_4b50 else { break }
        let nameLength = uint16(offset + 28)
        let extraLength = uint16(offset + 30)
        let commentLength = uint16(offset + 32)
        names.append(String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self))
        offset += 46 + nameLength + extraLength + commentLength
    }
    return names
}

extension PackageExportModel {
    /// The package the last export wrote, once it has finished.
    var exportedPackage: ExportedPackage? {
        if case .finished(let package) = step { package } else { nil }
    }
}

extension CollectionStore {
    /// Imports a package as a learner would, through the core: a collection
    /// package replaces the collection; a deck package is merged in with its
    /// scheduling and deck presets.
    func importPackage(at url: URL) async throws {
        if url.pathExtension == "colpkg" {
            try await replace { core, location in
                try await core.importCollectionPackage(.with {
                    $0.colPath = location.collectionFile.path
                    $0.backupPath = url.path
                    $0.mediaFolder = location.mediaFolder.path
                    $0.mediaDb = location.mediaDatabase.path
                })
            }
        } else {
            try await modify(.importAnkiPackage(.with {
                $0.packagePath = url.path
                $0.options.withScheduling = true
                $0.options.withDeckConfigs = true
            }))
        }
    }
}
