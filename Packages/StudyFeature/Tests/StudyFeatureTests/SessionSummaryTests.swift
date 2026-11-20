import AnkiCore
import CollectionTesting
import Foundation
import StudyFeature
import Testing

@MainActor
@Suite("What the finished screen reports about the session")
struct SessionSummaryTests {
    @Test("The summary counts each rating given in the session")
    func ratingBreakdown() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            try await store.addBasicNotes(count: 2, toDeck: deck)
            let session = StudySessionModel(store: store, deckID: deck)
            await session.start()

            // Again and Hard keep a new card in learning; Easy sends it away.
            for rating in [Rating.again, .hard, .easy] {
                session.showAnswer()
                await session.answer(rating)
            }
            var easy = 1
            while session.state.question != nil {
                session.showAnswer()
                await session.answer(.easy)
                easy += 1
                try #require(easy <= 4, "the session should end")
            }

            let summary = try #require(session.state.finished)
            #expect(summary.ratings[.again] == 1)
            #expect(summary.ratings[.hard] == 1)
            #expect(summary.ratings[.good] == 0)
            #expect(summary.ratings[.easy] == easy)
            #expect(summary.ratings.total == summary.reviewed)
        }
    }

    @Test("An undone review leaves the breakdown and the time; a redone one comes back")
    func undoAndRedo() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let card = try #require(try await store.addBasicNotes(count: 1, toDeck: deck).first)
            let session = StudySessionModel(store: store, deckID: deck)
            await session.start()
            session.showAnswer()
            await session.answer(.again)
            session.showAnswer()
            await session.answer(.easy)
            #expect(session.state.finished?.ratings[.easy] == 1)

            await session.undo()
            #expect(session.state.question?.id == card)
            session.showAnswer()
            await session.answer(.good)
            while session.state.question != nil {
                session.showAnswer()
                await session.answer(.easy)
            }

            var summary = try #require(session.state.finished)
            #expect(summary.ratings[.again] == 1)
            #expect(summary.ratings[.good] == 1)
            #expect(summary.ratings.total == summary.reviewed)

            // Undo the last review and redo it: the summary is the same again.
            let before = summary
            await session.undo()
            await session.redo()
            summary = try #require(session.state.finished)
            #expect(summary.ratings == before.ratings)
            #expect(summary.timeSpent == before.timeSpent)
        }
    }

    @Test("Time spent is the time the core recorded for the session's reviews")
    func timeSpent() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let cards = try await store.addBasicNotes(count: 2, toDeck: deck)
            let session = StudySessionModel(store: store, deckID: deck)
            await session.start()
            while session.state.question != nil {
                try await Task.sleep(for: .milliseconds(30))
                session.showAnswer()
                await session.answer(.easy)
            }

            var recorded = 0.0
            for card in cards {
                let logs = try await store.core.getReviewLogs(.with { $0.cid = card }).entries
                recorded += logs.reduce(0) { $0 + Double($1.takenSecs) }
            }
            let summary = try #require(session.state.finished)
            let seconds = Double(summary.timeSpent.components.seconds)
                + Double(summary.timeSpent.components.attoseconds) / 1e18
            #expect(recorded >= 0.06)
            #expect(abs(seconds - recorded) < 0.01)
        }
    }

    @Test("A session with no reviews has an empty breakdown and no time")
    func noReviews() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let session = StudySessionModel(store: store, deckID: deck)
            await session.start()

            let summary = try #require(session.state.finished)
            #expect(summary.ratings.total == 0)
            #expect(summary.timeSpent == .zero)
        }
    }
}
