import CollectionStore
import CollectionTesting
import StudyFeature
import Testing

@MainActor
@Suite("Typing the answer", .timeLimit(.minutes(1)))
struct TypedAnswerTests {
    @Test("A typed-answer fixture card shows a text field on the question side")
    func fieldOnQuestion() async throws {
        try await withTemporaryCollection { store in
            try await store.importFixture(.typedAnswerDeck)
            let session = try await store.studySession(ofCardsMatching: "Capital of Japan")

            let card = try #require(session.state.question)
            #expect(card.asksForTypedAnswer)
            #expect(card.question.html.contains("Capital of Japan"))
            #expect(card.question.html.contains("<input"))
            #expect(card.question.html.contains("id=typeans"))
            #expect(!card.question.html.contains("[[type:"))
            #expect(!card.question.html.contains("Tokyo"), "the question does not give the answer away")
        }
    }

    @Test("Typing the right answer shows it marked correct")
    func rightAnswer() async throws {
        try await withTemporaryCollection { store in
            try await store.importFixture(.typedAnswerDeck)
            let session = try await store.studySession(ofCardsMatching: "Capital of Japan")

            await session.showAnswer(typed: "Tokyo")

            let answer = try #require(session.state.answer).answer.html
            #expect(answer.contains("<code id=typeans><span class=typeGood>Tokyo</span></code>"))
            #expect(!answer.contains("typeBad"))
            #expect(!answer.contains("[[type:"))
            #expect(!answer.contains("<input"))
        }
    }

    @Test("Typing a wrong answer shows the core's comparison: what was typed, marked, above the right answer")
    func wrongAnswer() async throws {
        try await withTemporaryCollection { store in
            try await store.importFixture(.typedAnswerDeck)
            let session = try await store.studySession(ofCardsMatching: "Capital of Japan")

            await session.showAnswer(typed: "Tokio")

            let answer = try #require(session.state.answer).answer.html
            let comparison = try #require(answer.firstMatch(of: /<code id=typeans>(.*)<\/code>/)).output.1
            #expect(comparison.contains("typeBad"))
            #expect(comparison.contains("typeGood"))
            #expect(comparison.contains("id=typearrow"))
            // What was typed comes first, the expected answer below the arrow.
            let arrow = try #require(comparison.firstRange(of: "typearrow"))
            #expect(comparison[..<arrow.lowerBound].contains("i"))
            #expect(comparison[arrow.upperBound...].contains("y"))
            // The separator stays above the comparison.
            let separator = try #require(answer.firstRange(of: "<hr id=answer>"))
            #expect(separator.upperBound <= answer.firstRange(of: "<code id=typeans>")!.lowerBound)
        }
    }

    @Test("Showing the answer without typing shows the expected answer")
    func nothingTyped() async throws {
        try await withTemporaryCollection { store in
            try await store.importFixture(.typedAnswerDeck)
            let session = try await store.studySession(ofCardsMatching: "Largest planet")

            session.showAnswer()

            let answer = try #require(session.state.answer).answer.html
            #expect(answer.contains("<code id=typeans>Jupiter</code>"))
        }
    }

    @Test("A card that asks for no typing ignores typed text")
    func notATypingCard() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Plain")
            try await store.addBasicNotes(count: 1, toDeck: deck)
            let session = StudySessionModel(store: store, deckID: deck)
            await session.start()
            #expect(session.state.question?.asksForTypedAnswer == false)

            await session.showAnswer(typed: "anything")

            let answer = try #require(session.state.answer).answer.html
            #expect(answer.contains("Answer 0"))
            #expect(!answer.contains("typeans"))
        }
    }

    @Test("Typing a cloze deletion compares with that card's deletion only")
    func typedCloze() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Capitals")
            try await store.addNotes(ofType: "Cloze", fields: [
                ["{{c1::Paris}} is the capital of {{c2::France}}.", ""],
            ], toDeck: deck)
            try await store.addTypingToClozeTemplate()
            let session = StudySessionModel(store: store, deckID: deck)
            await session.start()
            let card = try #require(session.state.question)
            #expect(card.asksForTypedAnswer)
            let deletion = card.bodyClass == "card card1" ? "Paris" : "France"

            await session.showAnswer(typed: deletion)

            let answer = try #require(session.state.answer).answer.html
            #expect(answer.contains("<code id=typeans><span class=typeGood>\(deletion)</span></code>"))
        }
    }
}

private extension CollectionStore {
    /// Adds `{{type:cloze:Text}}` to the stock Cloze note type's question
    /// and answer, as learners do to type cloze deletions.
    func addTypingToClozeTemplate() async throws {
        let id = try await core.getNotetypeIdByName(.with { $0.val = "Cloze" })
        var notetype = try await core.getNotetype(id)
        notetype.templates[0].config.qFormat += "\n{{type:cloze:Text}}"
        notetype.templates[0].config.aFormat += "\n{{type:cloze:Text}}"
        try await modify(.updateNotetype(notetype))
    }
}
