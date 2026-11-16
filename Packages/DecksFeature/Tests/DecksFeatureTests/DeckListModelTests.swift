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
