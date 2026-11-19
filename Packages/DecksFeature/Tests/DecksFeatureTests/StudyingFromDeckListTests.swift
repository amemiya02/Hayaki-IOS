import CollectionTesting
import DecksFeature
import StudyFeature
import Testing

@MainActor
@Suite("Studying from the deck list", .timeLimit(.minutes(1)))
struct StudyingFromDeckListTests {
    @Test("The deck list's counts are current when the learner comes back from studying")
    func countsCurrentAfterStudying() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Languages::Spanish")
            try await store.addBasicNotes(count: 3, toDeck: spanish)
            let deckList = DeckListModel(store: store)
            let shown = Task { await deckList.run() }
            defer { shown.cancel() }
            try await eventually("the deck list loaded") {
                deckList.outline == ["Languages: 3 new, 0 learning, 0 due", "  Spanish: 3 new, 0 learning, 0 due"]
            }
            #expect(deckList.dueToday == 3)
            #expect(deckList.studiedToday == 0)

            // Study the parent deck: one card answered Easy, one Again.
            let languages = try await store.deckID(named: "Languages")
            let session = StudySessionModel(store: store, deckID: languages)
            await session.start()
            session.showAnswer()
            await session.answer(.easy)
            session.showAnswer()
            await session.answer(.again)

            try await eventually("the studied cards counted") {
                deckList.outline == ["Languages: 1 new, 1 learning, 0 due", "  Spanish: 1 new, 1 learning, 0 due"]
            }
            #expect(deckList.dueToday == 2)
            #expect(deckList.studiedToday == 2)
            #expect(session.counts == StudyCounts(new: 1, learning: 1, due: 0))
        }
    }
}
