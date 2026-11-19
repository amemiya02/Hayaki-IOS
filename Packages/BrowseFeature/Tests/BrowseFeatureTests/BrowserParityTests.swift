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

extension BrowserParityTests {
    @Test("Visible columns and sort order are independent per mode and survive reopening Browse")
    func columnsAndSort() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Languages")
            try await store.addBasicCard(front: "alpha", back: "First answer", inDeck: deck, tags: ["language"])
            try await store.addBasicCard(front: "beta", back: "Second answer", inDeck: deck)
            let model = CardBrowserModel(store: store)
            await model.search()
            #expect(model.visibleColumnIDs == ["noteFld", "template", "cardDue", "deck"])
            await model.setColumns(["answer", "noteFld"])
            await model.setSort(CardSort(column: "noteFld", reverse: true))
            let first = try #require(model.rowIDs.first)
            await model.loadRow(first)
            #expect(model.row(for: first)?.cells == ["answer": "Second answer", "noteFld": "beta"])

            await model.setMode(.notes)
            #expect(model.visibleColumnIDs == ["noteFld", "note", "template", "noteTags"])
            #expect(model.sort == .default)
            await model.setColumns(["noteTags", "noteFld"])
            await model.setColumns([])
            #expect(model.visibleColumnIDs == ["noteTags", "noteFld"])

            let reopened = CardBrowserModel(store: store)
            await reopened.search()
            #expect(reopened.mode == .notes)
            #expect(reopened.visibleColumnIDs == ["noteTags", "noteFld"])

            await reopened.setMode(.cards)
            #expect(reopened.visibleColumnIDs == ["answer", "noteFld"])
            #expect(reopened.sort == CardSort(column: "noteFld", reverse: true))
        }
    }
}

extension BrowserParityTests {
    @Test("Saved searches keep the submitted query in shared collection settings")
    func savedSearches() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish Verbs")
            let card = try await store.addBasicCard(front: "correr", back: "run", inDeck: deck)
            let model = CardBrowserModel(store: store)
            await model.applyFilter(.deck("Spanish Verbs"))
            let query = model.searchedText
            model.searchText = "unsubmitted draft"
            await model.saveSearch(named: "Verbs")
            await model.saveSearch(named: "Verbs")

            let reopened = CardBrowserModel(store: store)
            await reopened.loadSavedSearches()
            #expect(reopened.savedSearches.map(\.name) == ["Verbs"])
            #expect(reopened.savedSearches.map(\.query) == [query])
            await reopened.openSavedSearch(try #require(reopened.savedSearches.first))
            #expect(reopened.rowIDs == [card])
            #expect(reopened.searchText == query)

            await reopened.removeSavedSearch(named: "Verbs")
            await model.loadSavedSearches()
            #expect(model.savedSearches.isEmpty)
        }
    }
}
