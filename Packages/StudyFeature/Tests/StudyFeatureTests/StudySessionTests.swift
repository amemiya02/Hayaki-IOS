import CollectionTesting
import Foundation
import StudyFeature
import Testing

@MainActor
@Suite("Studying a deck", .timeLimit(.minutes(1)))
struct StudySessionTests {
    @Test("Starting a deck shows the question side of its first card, with today's counts")
    func startShowsFirstQuestion() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            try await store.addBasicNotes(count: 2, toDeck: spanish)

            let session = StudySessionModel(store: store, deckID: spanish)
            await session.start()

            let card = try #require(session.state.question)
            #expect(card.question.html.contains("Question 0"))
            #expect(!card.question.html.contains("Answer 0"))
            #expect(session.counts == StudyCounts(new: 2, learning: 0, due: 0))
        }
    }

    @Test("Revealing shows the answer side, which for Basic repeats the question above the answer")
    func revealShowsAnswer() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            try await store.addBasicNotes(count: 1, toDeck: spanish)
            let session = StudySessionModel(store: store, deckID: spanish)
            await session.start()

            session.showAnswer()

            let card = try #require(session.state.answer)
            #expect(session.state.question == nil)
            let answer = card.answer.html
            let question = try #require(answer.range(of: "Question 0"))
            let separator = try #require(answer.range(of: "<hr id=answer>"))
            let back = try #require(answer.range(of: "Answer 0"))
            #expect(question.upperBound <= separator.lowerBound && separator.upperBound <= back.lowerBound)
        }
    }

    @Test("Each rating shows the interval the core says it would give")
    func intervalsOnRatings() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let cardID = try #require(try await store.addBasicNotes(count: 1, toDeck: spanish).first)
            let session = StudySessionModel(store: store, deckID: spanish)
            await session.start()

            let card = try #require(session.state.question)
            let states = try await store.core.getSchedulingStates(.with { $0.cid = cardID })
            let described = try await store.core.describeNextStates(states).vals
                .map { $0.filter { !"\u{2068}\u{2069}".contains($0) } }
            #expect(Rating.allCases.map { card.intervals[$0] } == described)
            // A new card answered Easy leaves learning at once, so Easy's
            // interval is a different, longer one than Again's.
            #expect(card.intervals[.easy] != card.intervals[.again])
            #expect(Rating.allCases.allSatisfy { !card.intervals[$0].isEmpty })
        }
    }

    @Test("Rating a card records the review, moves on to the next card and the counts drop")
    func ratingMovesOn() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            try await store.addBasicNotes(count: 2, toDeck: spanish)
            let session = StudySessionModel(store: store, deckID: spanish)
            await session.start()
            let first = try #require(session.state.question)

            session.showAnswer()
            await session.answer(.easy)

            let second = try #require(session.state.question)
            #expect(second.id != first.id)
            #expect(session.counts == StudyCounts(new: 1, learning: 0, due: 0))
            #expect(session.reviewedCount == 1)
            #expect(try await store.reviewCount(matching: "cid:\(first.id)") == 1)
        }
    }

    @Test(
        "Again, Hard and Good keep a new card in learning, so it comes back today; Easy sends it away",
        arguments: Rating.allCases
    )
    func eachRating(rating: Rating) async throws {
        try await withTemporaryCollection { store in
            // Keep the next day rollover hours away, so a learning step a few
            // minutes ahead always falls on the same scheduler day.
            let rollover = Calendar.current.component(.hour, from: Date.now.addingTimeInterval(12 * 3600))
            try await store.updateSchedulingPreferences { $0.rollover = UInt32(rollover) }
            let spanish = try await store.addDeck(named: "Spanish")
            try await store.addBasicNotes(count: 1, toDeck: spanish)
            let session = StudySessionModel(store: store, deckID: spanish)
            await session.start()
            let card = try #require(session.state.question)

            session.showAnswer()
            await session.answer(rating)

            let logs = try await store.core.getReviewLogs(.with { $0.cid = card.id }).entries
            #expect(logs.map(\.buttonChosen) == [UInt32(Rating.allCases.firstIndex(of: rating)! + 1)])
            if rating == .easy {
                #expect(session.state.finished != nil)
                #expect(session.counts == StudyCounts(new: 0, learning: 0, due: 0))
            } else {
                // Learning steps are minutes away, within Anki's learn-ahead
                // limit, so the same card is shown again straight away.
                #expect(session.state.question?.id == card.id)
                #expect(session.counts == StudyCounts(new: 0, learning: 1, due: 0))
            }
        }
    }

    @Test("Review cards due today are counted as due, and the count drops as they are answered")
    func dueReviewCards() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            try await store.makeDueToday(store.addBasicNotes(count: 2, toDeck: spanish))
            let session = StudySessionModel(store: store, deckID: spanish)
            await session.start()
            #expect(session.counts == StudyCounts(new: 0, learning: 0, due: 2))

            session.showAnswer()
            await session.answer(.good)

            #expect(session.counts == StudyCounts(new: 0, learning: 0, due: 1))
            #expect(session.state.question != nil)
        }
    }

    @Test("Studying a fixture collection's deck to the end finishes the session with a summary")
    func studyFixtureDeckToTheEnd() async throws {
        try await withTemporaryCollection { store in
            try await store.importFixture(.collection)
            let languages = try await store.deckID(named: "Languages")
            let session = StudySessionModel(store: store, deckID: languages)
            await session.start()
            var remaining = session.counts.new + session.counts.learning + session.counts.due
            #expect(remaining > 0)

            var reviews = 0
            while let card = session.state.question {
                #expect(!card.question.html.isEmpty)
                session.showAnswer()
                await session.answer(.easy)
                reviews += 1
                let left = session.counts.new + session.counts.learning + session.counts.due
                #expect(left < remaining, "each Easy answer takes a card out of today's study")
                remaining = left
                try #require(reviews <= 10, "the session should end")
            }

            let summary = try #require(session.state.finished)
            #expect(summary.reviewed == reviews)
            // The core's line covers the whole collection's studying today.
            #expect(summary.studiedToday.hasPrefix("Studied "))
            #expect(session.counts == StudyCounts(new: 0, learning: 0, due: 0))
            // A new session over the finished deck has nothing to show.
            let again = StudySessionModel(store: store, deckID: languages)
            await again.start()
            #expect(again.state.finished?.reviewed == 0)
        }
    }

    @Test("While the session runs, editing the shown card's note redraws the same card and side with the new content")
    func noteEditedMidSession() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            try await store.addBasicNotes(count: 2, toDeck: spanish)
            let session = StudySessionModel(store: store, deckID: spanish)
            let shown = Task { await session.run() }
            defer { shown.cancel() }
            try await eventually("the first card shown") { session.state.question != nil }
            session.showAnswer()
            let card = try #require(session.state.answer)

            var note = try await store.core.getNote(.with { $0.nid = card.noteID })
            note.fields[1] = "Corrected answer"
            try await store.modify(.updateNotes(.with { $0.notes = [note] }))

            try await eventually("the corrected answer shown") {
                session.state.answer?.answer.html.contains("Corrected answer") == true
            }
            #expect(session.state.answer?.id == card.id)
            #expect(session.reviewedCount == 0)
        }
    }

    @Test("A deck with nothing left for today shows the finished state at once")
    func nothingToStudy() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            try await store.suspend(store.addBasicNotes(count: 1, toDeck: spanish))
            let session = StudySessionModel(store: store, deckID: spanish)
            await session.start()

            let summary = try #require(session.state.finished)
            #expect(summary.reviewed == 0)
            #expect(summary.learningLaterToday == 0)
        }
    }
}
