import BrowseFeature
import CollectionStore
import CollectionTesting
import Testing

@MainActor
@Suite("Browse rows", .timeLimit(.minutes(1)))
struct BrowseRowTests {
    @Test("A row shows the sort field, the deck and the due date, whatever columns are shown")
    func rowsSummarizeTheCard() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let gato = try await store.addBasicCard(front: "gato", back: "cat", inDeck: spanish)

            let model = CardBrowserModel(store: store)
            await model.search()
            await model.setColumns(["template", "noteTags"])
            await model.loadRow(gato)

            let row = try #require(model.row(for: gato))
            #expect(row.sortField == "gato")
            #expect(row.deck == "Spanish")
            // A new card's due column shows its position in the new queue.
            #expect(!row.due.isEmpty)
            // The other shown columns stay available as details, without
            // repeating the sort field, deck or due date.
            #expect(row.detailColumns(model.visibleColumns).map(\.id) == ["template", "noteTags"])
        }
    }

    @Test("Shown columns that the summary already covers are not repeated as details")
    func detailsSkipTheSummary() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let gato = try await store.addBasicCard(front: "gato", back: "cat", inDeck: spanish)

            let model = CardBrowserModel(store: store)
            await model.search()
            // The default columns: sort field, card, due and deck.
            await model.loadRow(gato)

            let row = try #require(model.row(for: gato))
            #expect(row.detailColumns(model.visibleColumns).map(\.id) == ["template"])
        }
    }

    @Test("A row tells whether its card is flagged or suspended")
    func flaggedAndSuspendedRows() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let gato = try await store.addBasicCard(front: "gato", back: "cat", inDeck: spanish)
            let perro = try await store.addBasicCard(front: "perro", back: "dog", inDeck: spanish)
            let model = CardBrowserModel(store: store)
            await model.search()

            model.selection = [gato]
            await model.perform(.flag(.green))
            try await store.suspend([perro])
            await model.search()
            await model.loadRow(gato)
            await model.loadRow(perro)

            #expect(model.row(for: gato)?.flag == .green)
            #expect(model.row(for: gato)?.isDimmed == false)
            #expect(model.row(for: perro)?.flag == nil)
            #expect(model.row(for: perro)?.isDimmed == true)
        }
    }
}
