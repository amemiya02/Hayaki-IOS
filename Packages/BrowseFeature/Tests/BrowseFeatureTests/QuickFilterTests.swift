import BrowseFeature
import CollectionStore
import CollectionTesting
import Foundation
import Testing

@MainActor
@Suite("Quick filters", .timeLimit(.minutes(1)))
struct QuickFilterTests {
    @Test("The deck filter lists the cards of a deck and its subdecks, and offers every deck")
    func deckFilter() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let verbs = try await store.addDeck(named: "Spanish::Verbs (irregular)")
            let geography = try await store.addDeck(named: "Geography")
            try await store.addBasicCard(front: "perro", back: "dog", inDeck: spanish)
            try await store.addBasicCard(front: "ser", back: "to be", inDeck: verbs)
            try await store.addBasicCard(front: "Capital of Peru", back: "Lima", inDeck: geography)
            let model = CardBrowserModel(store: store)
            await model.loadChoices()

            #expect(model.choices.decks == ["Geography", "Spanish", "Spanish::Verbs (irregular)"])

            await model.applyFilter(.deck("Spanish"))
            #expect(model.state == .loaded)
            #expect(await model.shownFronts() == ["perro", "ser"])
            // The search field shows the search in Anki's syntax.
            #expect(model.searchText == "deck:Spanish")

            // Names with characters that mean something in a search work too.
            await model.applyFilter(.deck("Spanish::Verbs (irregular)"))
            #expect(model.state == .loaded)
            #expect(await model.shownFronts() == ["ser"])
        }
    }

    @Test("The tag filter lists the cards whose note has a tag, and offers every tag")
    func tagFilter() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            try await store.addBasicCard(front: "perro", back: "dog", inDeck: deck, tags: ["animals"])
            try await store.addBasicCard(front: "rojo", back: "red", inDeck: deck, tags: ["colours"])
            try await store.addBasicCard(front: "gato", back: "cat", inDeck: deck, tags: ["animals", "pets"])
            let model = CardBrowserModel(store: store)
            await model.loadChoices()

            #expect(model.choices.tags == ["animals", "colours", "pets"])

            await model.applyFilter(.tag("animals"))
            #expect(await model.shownFronts() == ["gato", "perro"])
            #expect(model.searchText == "tag:animals")
        }
    }

    @Test("The flag filter lists the cards with that flag")
    func flagFilter() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let perro = try await store.addBasicCard(front: "perro", back: "dog", inDeck: deck)
            let gato = try await store.addBasicCard(front: "gato", back: "cat", inDeck: deck)
            try await store.addBasicCard(front: "rojo", back: "red", inDeck: deck)
            let model = CardBrowserModel(store: store)
            await model.search()
            model.selection = [perro]
            await model.perform(.flag(.red))
            model.selection = [gato]
            await model.perform(.flag(.blue))

            await model.applyFilter(.flag(.red))
            #expect(await model.shownFronts() == ["perro"])
            await model.applyFilter(.flag(.blue))
            #expect(await model.shownFronts() == ["gato"])
            await model.applyFilter(.flag(.green))
            #expect(model.state == .loaded)
            #expect(model.cardIDs.isEmpty)
        }
    }

    @Test("The suspended filter lists the suspended cards")
    func suspendedFilter() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let perro = try await store.addBasicCard(front: "perro", back: "dog", inDeck: deck)
            try await store.addBasicCard(front: "gato", back: "cat", inDeck: deck)
            try await store.suspend([perro])
            let model = CardBrowserModel(store: store)

            await model.applyFilter(.suspended)
            #expect(await model.shownFronts() == ["perro"])
            #expect(model.searchText == "is:suspended")
        }
    }

    @Test("The due today filter lists the cards waiting to be reviewed today, overdue ones included")
    func dueTodayFilter() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let perro = try await store.addBasicCard(front: "perro", back: "dog", inDeck: deck)
            let gato = try await store.addBasicCard(front: "gato", back: "cat", inDeck: deck)
            let rojo = try await store.addBasicCard(front: "rojo", back: "red", inDeck: deck)
            // A new card is not due; a review card due later is not either.
            try await store.addBasicCard(front: "verde", back: "green", inDeck: deck)
            try await store.makeDueToday([perro])
            try await store.makeOverdue(byDays: 3, [gato])
            #expect(try await store.cardCount(matching: "prop:due=-3") == 1)
            try await store.makeDue(inDays: 5, [rojo])
            let model = CardBrowserModel(store: store)

            await model.applyFilter(.dueToday)
            #expect(await model.shownFronts() == ["gato", "perro"])
            #expect(model.searchText == "is:due")
        }
    }
}
