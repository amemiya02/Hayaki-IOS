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
