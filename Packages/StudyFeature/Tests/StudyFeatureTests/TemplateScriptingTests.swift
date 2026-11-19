import AnkiCore
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

    @Test("Collection-wide template search and tagging require opt-in")
    func collectionPermission() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Templates")
            let cards = try await store.addBasicNotes(count: 2, toDeck: deck)
            let model = StudySessionModel(store: store, deckID: deck)
            await model.start()
            let card = try #require(model.state.card)
            let otherCardID = try #require(cards.first { $0 != card.id })
            let otherNoteID = try await store.core.getCard(.with { $0.cid = otherCardID }).noteID
            let addTag = TemplateRequest(
                command: "addTagToNote", version: "0.0.3", developer: "test@example.test",
                data: #"{"noteId":\#(otherNoteID),"tag":"scripted"}"#
            )
            let search = TemplateRequest(
                command: "searchCardWithCallback", version: "0.0.3", developer: "test@example.test",
                data: "tag:scripted"
            )

            let deniedSearch = await model.handleTemplate(search, cardID: card.id, isAnswer: false)
            #expect(deniedSearch == .unavailable)
            let deniedTag = await model.handleTemplate(addTag, cardID: card.id, isAnswer: false)
            #expect(deniedTag == .unavailable)

            let acceptedTag = await model.handleTemplate(addTag, cardID: card.id, isAnswer: false, allowsCollectionAccess: true)
            #expect(acceptedTag == .accepted)
            let acceptedSearch = await model.handleTemplate(search, cardID: card.id, isAnswer: false, allowsCollectionAccess: true)
            let matches = try #require(acceptedSearch.searchResults)
            #expect(matches.contains(String(otherNoteID)))
            #expect(matches.contains("fieldsData"))
        }
    }
}
