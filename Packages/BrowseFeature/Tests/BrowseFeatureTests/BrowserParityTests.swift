import BrowseFeature
import CollectionStore
import CollectionTesting
import Testing

@MainActor
@Suite("Browse parity")
struct BrowserParityTests {
    @Test("Notes mode shows one row per note and keeps the query when changing modes")
    func notesMode() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Geography")
            try await store.addNotes(ofType: "Basic (and reversed card)", fields: [
                ["Alpha", "A"],
                ["Beta", "B"],
            ], toDeck: deck)
            let model = CardBrowserModel(store: store)
            model.searchText = "deck:Geography"
            await model.search()
            #expect(model.rowIDs.count == 4)
            model.selectAll()

            await model.setMode(.notes)
            #expect(model.searchedText == "deck:Geography")
            #expect(model.rowIDs.count == 2)
            #expect(model.selection.isEmpty)
            let first = try #require(model.rowIDs.first)
            await model.loadRow(first)
            #expect(model.row(for: first)?.cells["noteFld"] == "Alpha")
            #expect(model.sortColumns.contains { $0.id == "noteFld" })

            await model.setMode(.cards)
            #expect(model.rowIDs.count == 4)
            #expect(model.searchedText == "deck:Geography")
        }
    }
}
