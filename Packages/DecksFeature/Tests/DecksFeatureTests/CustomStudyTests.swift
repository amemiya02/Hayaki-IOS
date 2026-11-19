import AnkiCore
import CollectionTesting
import DecksFeature
import Testing

@MainActor
@Suite("Custom study")
struct CustomStudyTests {
    @Test("Previewing recently added cards creates a filtered deck with no rescheduling")
    func previewRecentlyAddedCards() async throws {
        try await withTemporaryCollection { store in
            let source = try await store.addDeck(named: "Spanish")
            let other = try await store.addDeck(named: "Unrelated")
            let first = try #require(try await store.addBasicNotes(count: 1, toDeck: source).first)
            _ = try await store.addBasicNotes(count: 2, toDeck: other)
            let custom = CustomStudyModel(store: store, deckID: source)
            await custom.load()
            custom.choose(.previewNew)
            custom.amount = 7

            let result = try #require(await custom.start())

            #expect(result.id != source)
            let deck = try await store.core.getDeck(.with { $0.did = result.id })
            #expect(!deck.filtered.reschedule)
            let card = try await store.core.getCard(.with { $0.cid = first })
            #expect(card.deckID == result.id && card.originalDeckID == source)
        }
    }
}
