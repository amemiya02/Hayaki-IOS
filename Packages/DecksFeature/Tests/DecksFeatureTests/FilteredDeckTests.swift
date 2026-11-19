import AnkiCore
import CollectionTesting
import DecksFeature
import Testing

@MainActor
@Suite("Filtered decks")
struct FilteredDeckTests {
    @Test("A saved preview deck borrows matching cards and emptying returns them to their original decks")
    func previewDeckRoundTrip() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let japanese = try await store.addDeck(named: "Japanese")
            let one = try #require(try await store.addBasicNotes(count: 1, toDeck: spanish).first)
            let two = try #require(try await store.addBasicNotes(count: 1, toDeck: japanese).first)
            let model = FilteredDeckModel(store: store)

            await model.load()
            model.name = "Preview both"
            model.reschedule = false
            model.primary = FilteredDeckFilter(search: "deck:Spanish", limit: 1, order: .due)
            model.secondary = FilteredDeckFilter(search: "deck:Japanese", limit: 1, order: .added)

            let filtered = try #require(await model.build())

            let deck = try await store.core.getDeck(.with { $0.did = filtered })
            #expect(deck.filtered.searchTerms.map(\.search) == ["deck:Spanish", "deck:Japanese"])
            #expect(!deck.filtered.reschedule)
            #expect(Set(try await store.cardIDs(matching: #"deck:"Preview both""#)) == [one, two])
            await model.empty()
            #expect(try await store.cardIDs(matching: "deck:Spanish") == [one])
            #expect(try await store.cardIDs(matching: "deck:Japanese") == [two])
            #expect(try await store.reviewCount() == 0)
        }
    }
}
