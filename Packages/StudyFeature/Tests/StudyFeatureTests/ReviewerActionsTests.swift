import AnkiCore
import CollectionTesting
import StudyFeature
import Testing

@MainActor
@Suite("Reviewer actions")
struct ReviewerActionsTests {
    @Test("Undo restores a rated card and redo puts it back on its new schedule")
    func undoAndRedoRating() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let id = try #require(try await store.addBasicNotes(count: 1, toDeck: deck).first)
            let session = StudySessionModel(store: store, deckID: deck)
            await session.start()
            session.showAnswer()
            await session.answer(.easy)
            #expect(session.reviewedCount == 1)
            #expect(session.state.finished != nil)

            await session.undo()

            #expect(session.state.question?.id == id)
            #expect(session.counts.new == 1)
            #expect(session.reviewedCount == 0)
            #expect(try await store.reviewCount() == 0)

            await session.redo()

            #expect(session.state.finished != nil)
            #expect(session.reviewedCount == 1)
            #expect(try await store.reviewCount() == 1)
        }
    }

    @Test("Burying the current card clears the queue and unbury returns it")
    func buryAndUnbury() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let id = try #require(try await store.addBasicNotes(count: 1, toDeck: deck).first)
            let session = StudySessionModel(store: store, deckID: deck)
            await session.start()
            await session.bury(note: false)
            #expect(session.state.finished?.reason == .buried)
            #expect(try await store.cardIDs(matching: "is:buried") == [id])

            await session.unburyDeck()

            #expect(session.state.question?.id == id)
            #expect(try await store.cardIDs(matching: "is:buried").isEmpty)
        }
    }

    @Test("Flagging preserves the shown side and survives opening a new reviewer")
    func flagKeepsCurrentSide() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let id = try #require(try await store.addBasicNotes(count: 1, toDeck: deck).first)
            let session = StudySessionModel(store: store, deckID: deck)
            await session.start()
            session.showAnswer()
            await session.setFlag(3)

            #expect(session.state.answer?.id == id)
            #expect(session.state.answer?.flag == 3)
            #expect(try await store.cardIDs(matching: "flag:3") == [id])

            let reopened = StudySessionModel(store: store, deckID: deck)
            await reopened.start()
            #expect(reopened.state.question?.flag == 3)
        }
    }

    @Test("Marking a note toggles its built-in tag without changing the answer side")
    func markCurrentNote() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let id = try #require(try await store.addBasicNotes(count: 1, toDeck: deck).first)
            let session = StudySessionModel(store: store, deckID: deck)
            await session.start()
            session.showAnswer()

            await session.toggleMark()

            #expect(session.state.answer?.id == id)
            #expect(session.isCurrentNoteMarked)
            #expect(try await store.cardIDs(matching: "tag:marked") == [id])
            await session.toggleMark()
            #expect(!session.isCurrentNoteMarked)
            #expect(try await store.cardIDs(matching: "tag:marked").isEmpty)
        }
    }

    @Test("Moving the current card's due date to tomorrow advances the reviewer")
    func setDueTomorrow() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let id = try #require(try await store.addBasicNotes(count: 1, toDeck: deck).first)
            let session = StudySessionModel(store: store, deckID: deck)
            await session.start()

            await session.setDueDate("1")

            #expect(session.actionError == nil)
            #expect(session.state.finished?.reason == .done)
            #expect(try await store.cardIDs(matching: "prop:due=1") == [id])
            #expect(try await store.cardIDs(matching: "is:new").isEmpty)
        }
    }

    @Test("A suspended note leaves the queue and undo restores the card")
    func suspendAndUndo() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let id = try #require(try await store.addBasicNotes(count: 1, toDeck: deck).first)
            let session = StudySessionModel(store: store, deckID: deck)
            await session.start()

            await session.suspend(note: true)

            #expect(session.state.finished?.reason == .done)
            #expect(try await store.cardIDs(matching: "is:suspended") == [id])
            await session.undo()
            #expect(session.state.question?.id == id)
        }
    }

}
