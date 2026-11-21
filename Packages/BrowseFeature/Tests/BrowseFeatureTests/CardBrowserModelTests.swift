@testable import BrowseFeature
import CollectionStore
import CollectionTesting
import Foundation
import Testing

@MainActor
@Suite("Card browser", .timeLimit(.minutes(1)))
struct CardBrowserModelTests {
    @Test("Open browsers page their own modes and columns while retaining the last selected preference")
    func pagedRowsUseTheirBrowsersConfiguration() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let noteID = try #require(try await store.addNotes(
                ofType: "Basic (and reversed card)", fields: [["gato", "cat"]], toDeck: deck
            ).first)
            let cards = CardBrowserModel(store: store)
            await cards.search()
            await cards.setColumns(["deck", "noteFld"])

            let notes = CardBrowserModel(store: store)
            await notes.setMode(.notes)
            await notes.setColumns(["noteFld", "noteTags"])

            // The second card has an ID that cannot be resolved as this note.
            let cardID = try #require(cards.rowIDs.first(where: { $0 != noteID }))
            #expect(notes.rowIDs == [noteID])
            await cards.loadRow(cardID)
            #expect(cards.row(for: cardID)?.cells["deck"] == "Spanish")
            #expect(cards.row(for: cardID)?.cells["noteFld"] == "gato")
            await notes.loadRow(noteID)
            #expect(notes.row(for: noteID)?.cells["noteFld"] == "gato")

            let reopened = CardBrowserModel(store: store)
            await reopened.search()
            #expect(reopened.mode == .notes)
            #expect(reopened.visibleColumnIDs == ["noteFld", "noteTags"])
        }
    }

    @Test("With no search, the browser lists every card of the collection")
    func listsEveryCard() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let geography = try await store.addDeck(named: "Geography")
            try await store.addBasicCard(front: "perro", back: "dog", inDeck: spanish)
            try await store.addBasicCard(front: "gato", back: "cat", inDeck: spanish)
            try await store.addBasicCard(front: "Capital of Peru", back: "Lima", inDeck: geography)

            let model = CardBrowserModel(store: store)
            await model.search()

            #expect(model.state == .loaded)
            // Sorted by sort field (the front), as Anki sorts by default.
            #expect(await model.shownRows() == [
                "Capital of Peru | Geography",
                "gato | Spanish",
                "perro | Spanish",
            ])
        }
    }

    @Test("A search in Anki's syntax lists only the matching cards")
    func searchesWithAnkiSyntax() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let geography = try await store.addDeck(named: "Geography")
            try await store.addBasicCard(front: "perro", back: "dog", inDeck: spanish, tags: ["animals"])
            try await store.addBasicCard(front: "gato", back: "cat", inDeck: spanish, tags: ["animals"])
            try await store.addBasicCard(front: "Capital of Peru", back: "Lima", inDeck: geography)
            let model = CardBrowserModel(store: store)

            model.searchText = "deck:Spanish"
            await model.search()
            #expect(model.state == .loaded)
            #expect(await model.shownRows() == ["gato | Spanish", "perro | Spanish"])

            model.searchText = "back:dog or deck:Geo*"
            await model.search()
            #expect(await model.shownRows() == ["Capital of Peru | Geography", "perro | Spanish"])

            model.searchText = "-tag:animals"
            await model.search()
            #expect(await model.shownRows() == ["Capital of Peru | Geography"])

            model.searchText = "elephant"
            await model.search()
            #expect(model.state == .loaded)
            #expect(model.cardIDs.isEmpty)
        }
    }

    @Test("A search the core cannot understand shows the core's explanation")
    func invalidSearch() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            try await store.addBasicCard(front: "perro", back: "dog", inDeck: spanish)
            let model = CardBrowserModel(store: store)
            await model.search()
            #expect(model.cardIDs.count == 1)

            model.searchText = "deck:(Spanish"
            await model.search()

            guard case .invalidSearch(let message) = model.state else {
                Issue.record("Expected an invalid search, got \(model.state)")
                return
            }
            #expect(message.contains("Invalid search"))
            #expect(message.contains("closing bracket"))
            #expect(model.cardIDs.isEmpty)

            // Correcting the search lists cards again.
            model.searchText = "deck:Spanish"
            await model.search()
            #expect(model.state == .loaded)
            #expect(await model.shownRows() == ["perro | Spanish"])
        }
    }

    @Test("The learner can sort by any sortable column, either way round")
    func sorting() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Mixed")
            // Added in this order, so creation order differs from A to Z.
            try await store.addBasicCard(front: "gato", back: "cat", inDeck: deck)
            try await store.addBasicCard(front: "perro", back: "dog", inDeck: deck)
            try await store.addBasicCard(front: "Capital of Peru", back: "Lima", inDeck: deck)
            let model = CardBrowserModel(store: store)
            await model.search()

            let labels = model.sortColumns.map(\.label)
            #expect(labels.contains("Created"))
            #expect(labels.contains("Due"))
            #expect(labels.contains("Sort Field"))
            // The core cannot sort cards by their rendered question.
            #expect(!labels.contains("Question"))
            #expect(model.sort == .default)
            #expect(await model.shownFronts() == ["Capital of Peru", "gato", "perro"])

            // Choosing Created starts with the newest, as in Anki.
            let created = try #require(model.sortColumns.first { $0.label == "Created" })
            await model.sortBy(created)
            #expect(model.sort == CardSort(column: created.id, reverse: true))
            #expect(await model.shownFronts() == ["Capital of Peru", "perro", "gato"])

            await model.setSort(CardSort(column: created.id, reverse: false))
            #expect(await model.shownFronts() == ["gato", "perro", "Capital of Peru"])

            // Sorting keeps the current search.
            model.searchText = "-gato"
            await model.search()
            #expect(await model.shownFronts() == ["perro", "Capital of Peru"])
        }
    }

    @Test("While shown, the list follows cards added, studied and suspended elsewhere")
    func followsChanges() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let perro = try await store.addBasicCard(front: "perro", back: "dog", inDeck: spanish)
            let model = CardBrowserModel(store: store)
            let shown = Task { await model.run() }
            defer { shown.cancel() }
            try await eventually("the first card listed") { model.cardIDs == [perro] }
            await model.loadRow(perro)
            let newDue = try #require(model.row(for: perro)?.due)

            let gato = try await store.addBasicCard(front: "gato", back: "cat", inDeck: spanish)
            try await eventually("the added card listed") { model.cardIDs == [gato, perro] }

            // Studying the first new card, perro, changes when it is due.
            try await store.answerNextCard(inDeck: spanish, rating: .again)
            try await eventuallyAsync("the studied card's due date updated") {
                await model.loadRow(perro)
                return model.row(for: perro).map { $0.due != newDue } ?? false
            }

            try await store.suspend([perro])
            try await eventuallyAsync("the suspended card marked") {
                await model.loadRow(perro)
                return model.row(for: perro)?.mark == .suspended
            }
        }
    }

    @Test("Returning to Browse keeps loaded rows and refreshes after an offscreen change")
    func returningToBrowse() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let perro = try await store.addBasicCard(front: "perro", back: "dog", inDeck: deck)
            let model = CardBrowserModel(store: store)
            await model.refreshOnAppearance()
            await model.loadRow(perro)
            let initialGeneration = model.generation
            try #require(model.row(for: perro) != nil)

            await model.refreshOnAppearance()
            #expect(model.generation == initialGeneration)
            #expect(model.row(for: perro)?.question == "perro")

            let gato = try await store.addBasicCard(front: "gato", back: "cat", inDeck: deck)
            await model.refreshOnAppearance()
            #expect(model.cardIDs == [gato, perro])
            #expect(model.generation > initialGeneration)
        }
    }
}

extension CardBrowserModelTests {
    @Test("While shown, the list follows imported deck and collection packages")
    func followsImports() async throws {
        try await withTemporaryCollection { store in
            let model = CardBrowserModel(store: store)
            let shown = Task { await model.run() }
            defer { shown.cancel() }
            try await eventually("the empty collection listed") { model.state == .loaded }
            #expect(model.cardIDs.isEmpty)

            try await store.importFixture(.clozeDeck)
            try await eventually("the deck package's cards listed") { model.cardIDs.count == 3 }
            #expect(Set(await model.shownRows().map { $0.components(separatedBy: " | ").last })
                == ["Geography"])

            // A collection package replaces the collection, which the core
            // closes and opens again; the rows must still be fetched.
            try await store.importFixture(.collection)
            try await eventually("the collection package's cards listed") { model.cardIDs.count == 9 }
            #expect(Set(await model.shownRows().map { $0.components(separatedBy: " | ").last })
                == ["Geography", "Languages::Spanish", "Vocabulary"])
        }
    }
}

/// Waits until an async condition holds, checking every few milliseconds.
@MainActor
func eventuallyAsync(_ what: String, _ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while await !condition() {
        guard ContinuousClock.now < deadline else {
            throw StillFalse(description: "\(what) was still false after 5 seconds")
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

extension CardBrowserModel {
    /// The fronts of the listed cards, top to bottom.
    func shownFronts() async -> [String] {
        await shownRows().map { String($0.prefix { $0 != "|" }).trimmingCharacters(in: .whitespaces) }
    }

    /// The listed cards as a learner reads them, top to bottom: each card's
    /// question and deck.
    func shownRows() async -> [String] {
        var lines: [String] = []
        for id in cardIDs {
            await loadRow(id)
            guard let row = row(for: id) else {
                lines.append("(not loaded)")
                continue
            }
            lines.append("\(row.question) | \(row.deck)")
        }
        return lines
    }
}

struct StillFalse: Error, CustomStringConvertible {
    let description: String
}
