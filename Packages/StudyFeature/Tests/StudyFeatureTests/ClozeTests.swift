import CollectionStore
import CollectionTesting
import StudyFeature
import Testing

@MainActor
@Suite("Cloze deletions and maths", .timeLimit(.minutes(1)))
struct ClozeTests {
    @Test("A cloze deletion is hidden on the question side and revealed on the answer side")
    func clozeHiddenThenRevealed() async throws {
        try await withTemporaryCollection { store in
            try await store.importFixture(.clozeDeck)
            let session = try await store.studySession(ofCardsMatching: "card:1 Paris")

            // The text shown: the core keeps the deletion in a data-cloze
            // attribute, for scripts on the card.
            let question = try #require(session.state.question).question.html.replacing(/<[^>]*>/, with: "")
            #expect(question.contains("[...]"))
            #expect(!question.contains("Paris"))
            // The other deletion of the note is not this card's, so it shows.
            #expect(question.contains("France"))

            session.showAnswer()

            let answer = try #require(session.state.answer).answer.html
            #expect(answer.contains("Paris"))
            #expect(!answer.contains("[...]"))
            #expect(answer.contains("class=\"cloze\""))
        }
    }

    @Test("Maths written for MathJax reaches the card as MathJax, its deletion hidden until the answer")
    func mathJaxCloze() async throws {
        try await withTemporaryCollection { store in
            try await store.importFixture(.clozeDeck)
            let session = try await store.studySession(ofCardsMatching: "circle")

            let question = try #require(session.state.question).question.html
            #expect(!question.contains(#"\pi r^2"#))

            session.showAnswer()

            let answer = try #require(session.state.answer).answer.html
            #expect(answer.contains(#"\(\pi r^2\)"#))
        }
    }
}
