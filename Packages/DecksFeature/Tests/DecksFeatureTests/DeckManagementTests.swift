import AnkiCore
import CollectionTesting
import DecksFeature
import Testing

@MainActor
@Suite("Managing decks", .timeLimit(.minutes(1)))
struct DeckManagementTests {
    @Test("A created deck appears in the deck list at once")
    func createTopLevelDeck() async throws {
        try await withTemporaryCollection { store in
            let model = DeckListModel(store: store)
            await model.refresh()
            #expect(!model.hasOwnDecks)

            try await model.createDeck(named: "Spanish", inside: nil)

            #expect(model.outline == ["Spanish: 0 new, 0 learning, 0 due"])
            // Shown as a deck list, not as an empty collection, though it has
            // no cards yet.
            #expect(model.hasOwnDecks)
        }
    }

    @Test("A deck created inside another is shown under it, with its parent expanded")
    func createNestedDeck() async throws {
        try await withTemporaryCollection { store in
            let languages = try await store.addDeck(named: "Languages")
            try await store.addDeck(named: "Languages::Spanish")
            let model = DeckListModel(store: store)
            await model.refresh()
            try await model.setCollapsed(true, deck: languages)
            #expect(model.visibleDecks == ["Languages ▸"])

            let japanese = try await model.createDeck(named: "Japanese", inside: languages)
            let inside = try await model.createDeck(named: "Grammar", inside: japanese)

            #expect(model.visibleDecks == [
                "Languages ▾",
                "  Japanese ▾",
                "    Grammar",
                "  Spanish",
            ])
            #expect(try await store.deckNames().contains("Languages::Japanese::Grammar"))
            #expect(inside != japanese)
        }
    }

    @Test("Collapsing and expanding a parent deck is shown at once and remembered next time")
    func collapseIsRemembered() async throws {
        try await withTemporaryCollection { store in
            let model = DeckListModel(store: store)
            await model.refresh()
            let languages = try await model.createDeck(named: "Languages", inside: nil)
            try await model.createDeck(named: "Spanish", inside: languages)
            #expect(model.visibleDecks == ["Languages ▾", "  Spanish"])

            try await model.setCollapsed(true, deck: languages)
            #expect(model.visibleDecks == ["Languages ▸"])
            let nextTime = DeckListModel(store: store)
            await nextTime.refresh()
            #expect(nextTime.visibleDecks == ["Languages ▸"])

            try await nextTime.setCollapsed(false, deck: languages)
            #expect(nextTime.visibleDecks == ["Languages ▾", "  Spanish"])
            let timeAfter = DeckListModel(store: store)
            await timeAfter.refresh()
            #expect(timeAfter.visibleDecks == ["Languages ▾", "  Spanish"])
        }
    }

    @Test("A renamed deck keeps its place, its child decks and its cards")
    func renameDeck() async throws {
        try await withTemporaryCollection { store in
            let languages = try await store.addDeck(named: "Languages")
            let spanish = try await store.addDeck(named: "Languages::Spanish")
            try await store.addDeck(named: "Languages::Spanish::Verbs")
            try await store.addBasicNotes(count: 2, toDeck: spanish)
            let model = DeckListModel(store: store)
            await model.refresh()
            try await model.setCollapsed(false, deck: languages)
            try await model.setCollapsed(false, deck: spanish)

            try await model.renameDeck(spanish, to: "Español")

            #expect(model.outline == [
                "Languages: 2 new, 0 learning, 0 due",
                "  Español: 2 new, 0 learning, 0 due",
                "    Verbs: 0 new, 0 learning, 0 due",
            ])
            #expect(try await store.deckNames() == [
                "Default", "Languages", "Languages::Español", "Languages::Español::Verbs",
            ])
        }
    }

    @Test("Before deleting, the learner is told how many cards and child decks go with the deck")
    func deletionStatement() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let verbs = try await store.addDeck(named: "Spanish::Verbs")
            let french = try await store.addDeck(named: "French")
            try await store.addBasicNotes(count: 2, toDeck: spanish)
            // Cards in child decks go too, and so do suspended cards.
            try await store.addBasicNotes(count: 1, toDeck: verbs)
            try await store.suspend(store.addBasicNotes(count: 1, toDeck: verbs))
            try await store.addBasicNotes(count: 5, toDeck: french)
            let model = DeckListModel(store: store)
            await model.refresh()

            #expect(try await model.deletion(of: spanish) == DeckDeletion(cardCount: 4, subdeckCount: 1, isFiltered: false))
            #expect(try await model.deletion(of: verbs) == DeckDeletion(cardCount: 2, subdeckCount: 0, isFiltered: false))

            let deleted = try await model.deleteDeck(spanish)

            #expect(deleted == 4)
            #expect(model.outline == ["French: 5 new, 0 learning, 0 due"])
            #expect(try await store.deckNames() == ["Default", "French"])
            #expect(try await store.cardCount(matching: "") == 5)
        }
    }

    @Test("Deleting a filtered deck deletes no cards: they go back to their own deck")
    func deleteFilteredDeck() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            try await store.addBasicNotes(count: 3, toDeck: spanish)
            let cram = try await store.addFilteredDeck(named: "Cram", search: "deck:Spanish")
            let model = DeckListModel(store: store)
            await model.refresh()
            #expect(model.outline.contains("Cram: 3 new, 0 learning, 0 due"))

            #expect(try await model.deletion(of: cram) == DeckDeletion(cardCount: 0, subdeckCount: 0, isFiltered: true))
            #expect(try await model.deleteDeck(cram) == 0)

            #expect(model.outline == ["Spanish: 3 new, 0 learning, 0 due"])
        }
    }

    @Test("Deleting a deck whose cards a filtered deck has borrowed states those cards too")
    func deleteDeckWithBorrowedCards() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            try await store.addBasicNotes(count: 3, toDeck: spanish)
            try await store.addFilteredDeck(named: "Cram", search: "deck:Spanish")
            let model = DeckListModel(store: store)
            await model.refresh()

            let statedCount = try await model.deletion(of: spanish).cardCount
            let deleted = try await model.deleteDeck(spanish)

            #expect(statedCount == deleted)
            #expect(try await store.cardCount(matching: "") == 3 - deleted)
        }
    }

    @Test("A deck can be moved under another deck, with its child decks and cards, and back to the top level")
    func moveDeck() async throws {
        try await withTemporaryCollection { store in
            let languages = try await store.addDeck(named: "Languages")
            try await store.addDeck(named: "Languages::Japanese")
            let spanish = try await store.addDeck(named: "Spanish")
            try await store.addDeck(named: "Spanish::Verbs")
            try await store.addBasicNotes(count: 3, toDeck: spanish)
            let model = DeckListModel(store: store)
            await model.refresh()
            try await model.setCollapsed(true, deck: languages)
            try await model.setCollapsed(false, deck: spanish)

            try await model.moveDeck(spanish, under: languages)

            // The deck it went into is expanded, so the learner sees it there.
            #expect(model.visibleDecks == [
                "Languages ▾",
                "  Japanese",
                "  Spanish ▾",
                "    Verbs",
            ])
            #expect(model.outline.first == "Languages: 3 new, 0 learning, 0 due")
            #expect(model.parentID(of: spanish) == languages)

            try await model.moveDeck(spanish, under: nil)

            #expect(model.visibleDecks == [
                "Languages ▾",
                "  Japanese",
                "Spanish ▾",
                "  Verbs",
            ])
            #expect(model.parentID(of: spanish) == nil)
            #expect(try await store.deckNames() == [
                "Default", "Languages", "Languages::Japanese", "Spanish", "Spanish::Verbs",
            ])
        }
    }

    @Test("A name already used beside the deck is refused, rather than changed by the core")
    func clashingNames() async throws {
        try await withTemporaryCollection { store in
            let languages = try await store.addDeck(named: "Languages")
            try await store.addDeck(named: "Languages::Spanish")
            let spanish = try await store.addDeck(named: "Spanish")
            let french = try await store.addDeck(named: "French")
            let model = DeckListModel(store: store)
            await model.refresh()
            let before = try await store.deckNames()

            // Deck names are compared ignoring case, as Anki does.
            await #expect(throws: CoreError.self) { try await model.createDeck(named: "spanish", inside: nil) }
            await #expect(throws: CoreError.self) { try await model.renameDeck(french, to: "Spanish") }
            await #expect(throws: CoreError.self) { try await model.moveDeck(spanish, under: languages) }
            await #expect(throws: CoreError.self) { try await model.createDeck(named: "  ", inside: nil) }
            await #expect(throws: CoreError.self) { try await model.renameDeck(french, to: "") }
            #expect(try await store.deckNames() == before)

            // The same name elsewhere, or the deck's own name in other
            // letter case, is fine.
            try await model.createDeck(named: "French", inside: languages)
            try await model.renameDeck(french, to: "FRENCH")
            #expect(try await store.deckNames() == [
                "Default", "FRENCH", "Languages", "Languages::French", "Languages::Spanish", "Spanish",
            ])
        }
    }

    @Test("A deck cannot be moved into itself or its own child decks")
    func moveDestinations() async throws {
        try await withTemporaryCollection { store in
            let languages = try await store.addDeck(named: "Languages")
            try await store.addDeck(named: "Languages::Japanese::Kanji")
            try await store.addDeck(named: "Geography")
            let model = DeckListModel(store: store)
            await model.refresh()

            #expect(model.parentChoices(excludingSubtreeOf: languages).map(\.fullName) == ["Geography"])
            #expect(model.parentChoices().map(\.fullName) == [
                "Geography", "Languages", "Languages::Japanese", "Languages::Japanese::Kanji",
            ])
            #expect(model.parentChoices().map(\.depth) == [0, 0, 1, 2])
        }
    }
}

extension DeckListModel {
    /// The deck names a learner sees: children of collapsed decks are hidden;
    /// a parent is marked ▾ when expanded and ▸ when collapsed.
    var visibleDecks: [String] {
        func lines(_ decks: [DeckNode], depth: Int) -> [String] {
            decks.flatMap { deck in
                let indent = String(repeating: "  ", count: depth)
                if deck.children.isEmpty {
                    return [indent + deck.name]
                }
                if deck.isCollapsed {
                    return [indent + deck.name + " ▸"]
                }
                return [indent + deck.name + " ▾"] + lines(deck.children, depth: depth + 1)
            }
        }
        return lines(decks, depth: 0)
    }
}
