import CollectionTesting
import DecksFeature
import Testing

@MainActor
@Suite("Today card", .timeLimit(.minutes(1)))
struct TodaySummaryTests {
    @Test("Today's totals add up the top-level decks without counting subdecks twice")
    func totalsMatchTheDeckTree() async throws {
        try await withTemporaryCollection { store in
            let japanese = try await store.addDeck(named: "Languages::Japanese")
            let spanish = try await store.addDeck(named: "Languages::Spanish")
            let geography = try await store.addDeck(named: "Geography")
            try await store.addBasicNotes(count: 3, toDeck: japanese)
            try await store.addBasicNotes(count: 1, toDeck: spanish)
            try await store.answerNextCard(inDeck: spanish, rating: .again)
            try await store.makeDueToday(store.addBasicNotes(count: 2, toDeck: spanish))
            try await store.addBasicNotes(count: 4, toDeck: geography)

            let model = DeckListModel(store: store)
            await model.refresh()

            #expect(model.today == DeckCounts(new: 7, learning: 1, due: 2))
            #expect(model.dueToday == 10)
        }
    }

    @Test("Study All covers every top-level deck with cards left today, in list order")
    func studyAllCoversTheCollection() async throws {
        try await withTemporaryCollection { store in
            let japanese = try await store.addDeck(named: "Languages::Japanese")
            try await store.addDeck(named: "Empty")
            let geography = try await store.addDeck(named: "Geography")
            try await store.addBasicNotes(count: 2, toDeck: japanese)
            try await store.addBasicNotes(count: 1, toDeck: geography)

            let model = DeckListModel(store: store)
            await model.refresh()

            #expect(model.studyAllDecks.map(\.name) == ["Geography", "Languages"])
        }
    }

    @Test("When the collection is just the Default deck, Study All studies the Default deck")
    func studyAllUsesTheDefaultDeck() async throws {
        try await withTemporaryCollection { store in
            try await store.addBasicNotes(count: 2, toDeck: 1)

            let model = DeckListModel(store: store)
            await model.refresh()

            #expect(model.studyAllDecks.map(\.id) == [1])
            #expect(model.today == DeckCounts(new: 2, learning: 0, due: 0))
        }
    }

    @Test("Study All moves on to the next deck only once the studied deck is finished")
    func studyAllContinuesAfterAFinishedDeck() async throws {
        try await withTemporaryCollection { store in
            let geography = try await store.addDeck(named: "Geography")
            let history = try await store.addDeck(named: "History")
            try await store.addBasicNotes(count: 1, toDeck: geography)
            try await store.addBasicNotes(count: 1, toDeck: history)

            let model = DeckListModel(store: store)
            try await store.answerNextCard(inDeck: geography, rating: .easy)
            await model.refresh()
            #expect(model.nextStudyAllDeck(after: geography)?.name == "History")

            try await store.answerNextCard(inDeck: history, rating: .easy)
            await model.refresh()
            #expect(model.nextStudyAllDeck(after: history) == nil)
        }
    }

    @Test("Completing a deck advances to other work before revisiting the same deck")
    func studyAllRefreshesACompletedDeck() async throws {
        try await withTemporaryCollection { store in
            let geography = try await store.addDeck(named: "Geography")
            let history = try await store.addDeck(named: "History")
            try await store.addBasicNotes(count: 1, toDeck: geography)
            try await store.addBasicNotes(count: 1, toDeck: history)
            try await store.answerNextCard(inDeck: geography, rating: .easy)
            let model = DeckListModel(store: store)
            await model.refresh()
            #expect(model.nextStudyAllDeck(after: geography)?.id == history)

            // New work arrives while Geography's Finished screen is open.
            try await store.addBasicNotes(count: 1, toDeck: geography)
            await model.refresh()
            #expect(model.nextStudyAllDeck(after: geography)?.id == history)

            try await store.answerNextCard(inDeck: history, rating: .easy)
            await model.refresh()
            #expect(model.nextStudyAllDeck(after: geography)?.id == geography)
        }
    }

    @Test("With nothing left today, Study All has no deck to open")
    func studyAllEmptyWhenNothingIsDue() async throws {
        try await withTemporaryCollection { store in
            try await store.addDeck(named: "Spanish")

            let model = DeckListModel(store: store)
            await model.refresh()

            #expect(model.studyAllDecks.isEmpty)
            #expect(model.today.isEmpty)
        }
    }
}
