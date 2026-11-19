import AnkiCore
import CollectionTesting
import Foundation
import PackagesFeature
import Testing

@MainActor
@Suite("Delimited text export")
struct TextExportTests {
    @Test("A text export of one deck can be imported without picking up other decks")
    func deckTextRoundTrip() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let other = try await store.addDeck(named: "Japanese")
            try await store.addBasicNotes(count: 1, toDeck: spanish)
            try await store.addBasicNotes(count: 2, toDeck: other)
            let expected = try await store.snapshot(matching: "deck:Spanish").notes.map(\.fields)
            let folder = try TemporaryFolder()
            let model = TextExportModel(store: store, folder: folder.url, deckID: spanish)

            await model.export()

            let file = try #require(model.exportedFile)
            #expect(file.pathExtension == "txt")
            try await withTemporaryCollection { receiver in
                let imported = TextImportModel(store: receiver)
                await imported.prepare(file)
                await imported.startImport()
                #expect(imported.summary?.added == 1)
                let actual = try await receiver.snapshot().notes.map(\.fields)
                #expect(actual == expected)
            }
        }
    }
}

extension TextExportTests {
    @Test("Browse selection exports the chosen cards and notes without other results")
    func selection() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Languages")
            let selectedCard = try await store.addBasicCard(front: "selected", back: "retained", inDeck: deck)
            try await store.addBasicCard(front: "omitted", back: "excluded", inDeck: deck)
            let folder = try TemporaryFolder()
            let selected = ExportSelection.cards([selectedCard])
            let text = TextExportModel(store: store, folder: folder.url, selection: selected)
            await text.export()
            #expect(text.format == .cards)
            #expect(text.count == 1)
            let output = try String(contentsOf: #require(text.exportedFile), encoding: .utf8)
            #expect(output.contains("selected\tretained"))
            #expect(!output.contains("omitted"))

            let noteID = try await store.core.getCard(.with { $0.cid = selectedCard }).noteID
            let notes = TextExportModel(store: store, folder: folder.url, selection: .notes([noteID]))
            await notes.export()
            #expect(notes.format == .notes)
            #expect(notes.count == 1)
            let noteText = try String(contentsOf: #require(notes.exportedFile), encoding: .utf8)
            #expect(noteText.contains("selected\tretained"))
            #expect(!noteText.contains("omitted"))

            let archive = PackageExportModel(store: store, exportFolder: folder.url, selection: selected)
            await archive.export()
            guard case .finished(let package) = archive.step else {
                Issue.record("Expected deck package, got \(archive.step)")
                return
            }
            #expect(package.kind == .deckPackage)
            try await withTemporaryCollection { fresh in
                try await fresh.importPackage(at: package.url)
                #expect(try await fresh.cardCount(matching: "") == 1)
                #expect(try await fresh.cardCount(matching: "front:selected") == 1)
            }
        }
    }
}
