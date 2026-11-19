import CollectionTesting
@testable import StudyFeature
import Testing

@MainActor
@Suite("Card template scripting")
struct TemplateScriptingTests {
    @Test("A versioned template getter reads the actual queue and invalid contracts are rejected")
    func countsAndVersion() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Templates")
            try await store.addBasicNotes(count: 2, toDeck: deck)
            let model = StudySessionModel(store: store, deckID: deck)
            await model.start()
            let card = try #require(model.state.card)

            let result = await model.handleTemplate(
                .init(command: "newCardCount", version: "0.0.3", developer: "test@example.test"),
                cardID: card.id, isAnswer: false
            )
            #expect(result == .init(success: true, value: .integer(2)))

            let invalid = await model.handleTemplate(
                .init(command: "showAnswer", version: "0.0.2", developer: "test@example.test"),
                cardID: card.id, isAnswer: false
            )
            #expect(invalid == .invalid)
            #expect(model.state.question?.id == card.id)
        }
    }

    @Test("Template ratings reveal on the question, grade on the answer and reject a stale side")
    func sideAndStaleMutation() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Templates")
            try await store.addBasicNotes(count: 2, toDeck: deck)
            let model = StudySessionModel(store: store, deckID: deck)
            await model.start()
            let card = try #require(model.state.card)
            let request = TemplateRequest(command: "answerEase3", version: "0.0.3", developer: "test@example.test")

            let shown = await model.handleTemplate(request, cardID: card.id, isAnswer: false)
            #expect(shown == .accepted)
            #expect(model.state.answer?.id == card.id)
            #expect(model.reviewedCount == 0)

            let stale = await model.handleTemplate(request, cardID: card.id, isAnswer: false)
            #expect(stale == .unavailable)
            #expect(model.reviewedCount == 0)

            let graded = await model.handleTemplate(request, cardID: card.id, isAnswer: true)
            #expect(graded == .accepted)
            #expect(model.reviewedCount == 1)
        }
    }
}
