import AnkiCore
import CollectionTesting
import DecksFeature
import StudyFeature
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

extension FilteredDeckTests {
    @Test("Preview reviews preserve the schedule while rescheduling reviews update it", arguments: [false, true])
    func filteredReview(reschedule: Bool) async throws {
        try await withTemporaryCollection { store in
            let source = try await store.addDeck(named: "Spanish")
            let id = try #require(try await store.addBasicNotes(count: 1, toDeck: source).first)
            try await store.makeDueToday([id])
            let before = try await store.core.getCard(.with { $0.cid = id })

            let filter = FilteredDeckModel(store: store)
            await filter.load()
            filter.name = "Today"
            filter.reschedule = reschedule
            filter.primary = FilteredDeckFilter(search: "deck:Spanish is:due", limit: 1, order: .due)
            let filtered = try #require(await filter.build())
            let session = StudySessionModel(store: store, deckID: filtered)
            await session.start()
            #expect(session.state.question?.id == id)
            session.showAnswer()
            await session.answer(.easy)

            let after = try await store.core.getCard(.with { $0.cid = id })
            #expect(after.deckID == source)
            #expect(after.originalDeckID == 0)
            if reschedule {
                #expect(after.due > before.due)
            } else {
                #expect(after.due == before.due)
                #expect(after.interval == before.interval)
                #expect(session.state.finished?.isFiltered == true)

                await session.rebuildFinishedFilteredDeck()

                #expect(session.state.question?.id == id)
            }
        }
    }
}
