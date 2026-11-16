import CollectionTesting
import DecksFeature
import Testing

@MainActor
@Suite("Deck list", .timeLimit(.minutes(1)))
struct DeckListModelTests {
    @Test("A new collection shows only the Default deck, with nothing to study")
    func emptyCollection() async throws {
        try await withTemporaryCollection { store in
            let model = DeckListModel(store: store)
            await model.refresh()

            #expect(model.state == .loaded)
            #expect(model.outline == ["Default: 0 new, 0 learning, 0 due"])
        }
    }

    @Test("Decks are nested under their parents, each with today's new, learning and due counts")
    func nestedDecksWithCounts() async throws {
        try await withTemporaryCollection { store in
            let japanese = try await store.addDeck(named: "Languages::Japanese")
            let spanish = try await store.addDeck(named: "Languages::Spanish")
            let geography = try await store.addDeck(named: "Geography")
            // Japanese: three cards never studied.
            try await store.addBasicNotes(count: 3, toDeck: japanese)
            // Spanish: one card just failed, so it is in learning, and two
            // review cards due today.
            try await store.addBasicNotes(count: 1, toDeck: spanish)
            try await store.answerNextCard(inDeck: spanish, rating: .again)
            try await store.makeDueToday(store.addBasicNotes(count: 2, toDeck: spanish))
            // Geography: one new card, but it has been suspended.
            try await store.suspend(store.addBasicNotes(count: 1, toDeck: geography))

            let model = DeckListModel(store: store)
            await model.refresh()

            // The empty Default deck is hidden once other decks exist, as in Anki.
            #expect(model.outline == [
                "Geography: 0 new, 0 learning, 0 due",
                "Languages: 3 new, 1 learning, 2 due",
                "  Japanese: 3 new, 0 learning, 0 due",
                "  Spanish: 0 new, 1 learning, 2 due",
            ])
        }
    }

    @Test("While shown, the deck list updates itself after the collection changes")
    func refreshesAfterChanges() async throws {
        try await withTemporaryCollection { store in
            let model = DeckListModel(store: store)
            let shown = Task { await model.run() }
            defer { shown.cancel() }
            try await eventually("the deck list loaded") { model.state == .loaded }

            let spanish = try await store.addDeck(named: "Spanish")
            try await store.addBasicNotes(count: 2, toDeck: spanish)
            try await eventually("the new deck and its cards shown") {
                model.outline == ["Spanish: 2 new, 0 learning, 0 due"]
            }

            try await store.answerNextCard(inDeck: spanish, rating: .again)
            try await eventually("the studied card counted as learning") {
                model.outline == ["Spanish: 1 new, 1 learning, 0 due"]
            }
        }
    }

    @Test("A collection without cards counts as empty, so the first screen can offer an import")
    func emptyUntilCardsArrive() async throws {
        try await withTemporaryCollection { store in
            let model = DeckListModel(store: store)
            await model.refresh()
            #expect(model.hasNoCards)

            // Decks alone do not make it a collection to study.
            try await store.addDeck(named: "Spanish")
            await model.refresh()
            #expect(model.hasNoCards)

            // Suspended cards still count: they are the learner's cards.
            let spanish = try await store.deckID(named: "Spanish")
            try await store.suspend(store.addBasicNotes(count: 1, toDeck: spanish))
            await model.refresh()
            #expect(!model.hasNoCards)
        }
    }

    @Test("After a package is imported, the shown deck list updates without a restart")
    func refreshesAfterImport() async throws {
        try await withTemporaryCollection { store in
            let model = DeckListModel(store: store)
            let shown = Task { await model.run() }
            defer { shown.cancel() }
            try await eventually("the deck list loaded") { model.state == .loaded }

            try await store.importFixture(.basicDeck)
            try await eventually("the imported decks shown") {
                model.outline.first?.hasPrefix("Languages:") == true && !model.hasNoCards
            }

            try await store.importFixture(.collection)
            try await eventually("the replacing collection's decks shown") {
                model.outline.map { $0.components(separatedBy: ":").first ?? "" }
                    == ["Geography", "Languages", "  Spanish", "Vocabulary"]
            }
        }
    }
}

extension DeckListModel {
    /// The deck list as a learner reads it, one line per deck, children
    /// indented under their parent.
    var outline: [String] {
        func lines(_ decks: [DeckNode], depth: Int) -> [String] {
            decks.flatMap { deck in
                let line = String(repeating: "  ", count: depth)
                    + "\(deck.name): \(deck.counts.new) new, \(deck.counts.learning) learning, \(deck.counts.due) due"
                return [line] + lines(deck.children, depth: depth + 1)
            }
        }
        return lines(decks, depth: 0)
    }
}
