import BrowseFeature
import CollectionStore
import CollectionTesting
import Foundation
import Testing

@MainActor
@Suite("Bulk actions", .timeLimit(.minutes(1)))
struct BulkActionTests {
    @Test("The learner can select several cards, or every card listed, and clear the selection")
    func selecting() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let perro = try await store.addBasicCard(front: "perro", back: "dog", inDeck: deck)
            let gato = try await store.addBasicCard(front: "gato", back: "cat", inDeck: deck)
            let rojo = try await store.addBasicCard(front: "rojo", back: "red", inDeck: deck)
            let model = CardBrowserModel(store: store)
            await model.search()

            model.selection = [perro, gato]
            #expect(model.selection.count == 2)
            model.selectAll()
            #expect(model.selection == [perro, gato, rojo])
            model.clearSelection()
            #expect(model.selection.isEmpty)

            // A narrower search keeps only the selected cards it still lists.
            model.selectAll()
            model.searchText = "-rojo"
            await model.search()
            #expect(model.selection == [perro, gato])
        }
    }

    @Test("Suspending and unsuspending changes only the selected cards")
    func suspendAndUnsuspend() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let perro = try await store.addBasicCard(front: "perro", back: "dog", inDeck: deck)
            let gato = try await store.addBasicCard(front: "gato", back: "cat", inDeck: deck)
            let rojo = try await store.addBasicCard(front: "rojo", back: "red", inDeck: deck)
            let model = CardBrowserModel(store: store)
            await model.search()

            model.selection = [perro, gato]
            await model.perform(.suspend)
            #expect(model.failure == nil)
            #expect(await model.shownMarks() == ["gato: suspended", "perro: suspended", "rojo: none"])
            #expect(model.completedAction?.action == .suspend)
            #expect(model.completedAction?.cardCount == 2)
            #expect(try await store.cardCount(matching: "is:suspended") == 2)

            model.selection = [perro, rojo]
            await model.perform(.unsuspend)
            #expect(await model.shownMarks() == ["gato: suspended", "perro: none", "rojo: none"])
            #expect(try await store.cardCount(matching: "is:suspended") == 1)
        }
    }

    @Test("Flagging sets one flag on the selected cards, and can take it off again")
    func flagging() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let perro = try await store.addBasicCard(front: "perro", back: "dog", inDeck: deck)
            let gato = try await store.addBasicCard(front: "gato", back: "cat", inDeck: deck)
            try await store.addBasicCard(front: "rojo", back: "red", inDeck: deck)
            let model = CardBrowserModel(store: store)
            await model.search()

            model.selection = [perro, gato]
            await model.perform(.flag(.green))
            #expect(await model.shownMarks() == ["gato: green flag", "perro: green flag", "rojo: none"])

            // Another flag replaces it.
            model.selection = [gato]
            await model.perform(.flag(.purple))
            #expect(await model.shownMarks() == ["gato: purple flag", "perro: green flag", "rojo: none"])

            model.selection = [perro, gato]
            await model.perform(.flag(nil))
            #expect(await model.shownMarks() == ["gato: none", "perro: none", "rojo: none"])
        }
    }

    @Test("Moving puts the selected cards in another deck, which may be a subdeck; filtered decks are not offered")
    func moving() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let verbs = try await store.addDeck(named: "Spanish::Verbs")
            let perro = try await store.addBasicCard(front: "perro", back: "dog", inDeck: spanish)
            let gato = try await store.addBasicCard(front: "gato", back: "cat", inDeck: spanish)
            try await store.addBasicCard(front: "ser", back: "to be", inDeck: verbs)
            try await store.addFilteredDeck(named: "Cram", search: "ser")
            let model = CardBrowserModel(store: store)
            await model.search()
            await model.loadChoices()

            #expect(model.choices.decks.contains("Cram"))
            #expect(model.choices.moveDestinations.map(\.name) == ["Spanish", "Spanish::Verbs"])

            model.selection = [perro, gato]
            await model.perform(.move(toDeck: verbs))
            let moved = await model.shownRows()
            #expect(moved == [
                "gato | Spanish::Verbs",
                "perro | Spanish::Verbs",
                "ser | Cram (Spanish::Verbs)",
            ])
            #expect(model.completedAction?.cardCount == 2)
        }
    }

    @Test("Deleting asks first, saying how many notes and cards go, then deletes the notes of the selected cards")
    func deleting() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            // One note with two cards: front-to-back and back-to-front.
            try await store.addNotes(ofType: "Basic (and reversed card)", fields: [["casa", "house"]], toDeck: deck)
            let perro = try await store.addBasicCard(front: "perro", back: "dog", inDeck: deck)
            try await store.addBasicCard(front: "gato", back: "cat", inDeck: deck)
            let model = CardBrowserModel(store: store)
            await model.search()
            #expect(model.cardIDs.count == 4)
            let casaFront = try #require(try await store.cardIDs(matching: "front:casa card:1").first)

            model.selection = [casaFront, perro]
            let summary = try #require(await model.deletionSummary())
            // Deleting a card deletes its note, with the note's other cards.
            #expect(summary == DeletionSummary(noteCount: 2, cardCount: 3))

            await model.perform(.delete)
            #expect(model.failure == nil)
            #expect(await model.shownFronts() == ["gato"])
            #expect(model.selection.isEmpty)
            #expect(try await store.cardCount(matching: "") == 1)
            #expect(model.completedAction?.action == .delete)
            #expect(model.completedAction?.cardCount == 3)
        }
    }

    @Test("Each bulk action can be undone, bringing back the cards as they were")
    func undoing() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let other = try await store.addDeck(named: "Other")
            let perro = try await store.addBasicCard(front: "perro", back: "dog", inDeck: spanish)
            let gato = try await store.addBasicCard(front: "gato", back: "cat", inDeck: spanish)
            let model = CardBrowserModel(store: store)
            await model.search()
            let before = await model.shownMarksAndDecks()

            let actions: [BulkAction] = [.suspend, .flag(.red), .move(toDeck: other), .delete]
            for action in actions {
                model.selection = [perro, gato]
                await model.perform(action)
                #expect(await model.shownMarksAndDecks() != before, "\(action) changed nothing")
                // The core names the action, in its language.
                let name = try #require(model.completedAction?.undoName)
                #expect(!name.isEmpty)

                #expect(await model.undoLastAction())
                #expect(model.completedAction == nil)
                #expect(await model.shownMarksAndDecks() == before, "\(action) was not undone")
            }

            // Unsuspending is undone too.
            try await store.suspend([perro])
            await model.search()
            let suspended = await model.shownMarksAndDecks()
            model.selection = [perro]
            await model.perform(.unsuspend)
            #expect(await model.undoLastAction())
            #expect(await model.shownMarksAndDecks() == suspended)
        }
    }

    @Test("Undo leaves alone a later change made elsewhere")
    func undoAfterAnotherChange() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let perro = try await store.addBasicCard(front: "perro", back: "dog", inDeck: spanish)
            let model = CardBrowserModel(store: store)
            await model.search()

            model.selection = [perro]
            await model.perform(.suspend)
            // Something else is changed after the suspension.
            try await store.addDeck(named: "Geography")

            #expect(await model.undoLastAction() == false)
            #expect(model.completedAction == nil)
            #expect(try await store.deckNames().contains("Geography"))
            #expect(try await store.cardCount(matching: "is:suspended") == 1)
        }
    }
}

extension CardBrowserModel {
    /// Each listed card's front and mark, as a learner sees them.
    func shownMarks() async -> [String] {
        var lines: [String] = []
        for (id, front) in zip(cardIDs, await shownFronts()) {
            let mark = switch row(for: id)?.mark {
            case .none?: "none"
            case .suspended?: "suspended"
            case .buried?: "buried"
            case .marked?: "marked"
            case .flag(let flag)?: "\(flag) flag"
            case nil: "(not loaded)"
            }
            lines.append("\(front): \(mark)")
        }
        return lines
    }

    func shownMarksAndDecks() async -> [String] {
        let marks = await shownMarks()
        let rows = await shownRows()
        return zip(marks, rows).map { "\($0) | \($1)" }
    }
}
