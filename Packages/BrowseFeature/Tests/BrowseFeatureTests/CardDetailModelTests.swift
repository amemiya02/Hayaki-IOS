import BrowseFeature
import CollectionStore
import CollectionTesting
import Foundation
import Testing

@MainActor
@Suite("Card detail", .timeLimit(.minutes(1)))
struct CardDetailModelTests {
    @Test("A new card shows its note's fields, its deck and its place among new cards")
    func newCard() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Languages::Spanish")
            try await store.addBasicCard(front: "uno", back: "one", inDeck: spanish)
            let card = try await store.addBasicCard(front: "<b>perro</b>", back: "dog<br>(animal)", inDeck: spanish)

            let model = CardDetailModel(store: store, cardID: card)
            await model.refresh()

            let detail = try #require(model.detail)
            // Field content is shown as text, without its markup.
            #expect(detail.fields.map { "\($0.name): \($0.text)" } == ["Front: perro", "Back: dog (animal)"])
            #expect(detail.deck == "Languages::Spanish")
            #expect(detail.noteType == "Basic")
            #expect(detail.cardTemplate == "Card 1")
            #expect(Calendar.current.isDateInToday(detail.added))
            // The second new card added is studied second.
            #expect(detail.due == .newCardPosition(2))
            #expect(detail.status == .normal)
            #expect(detail.history.isEmpty)
            #expect(detail.reviewCount == 0)
        }
    }

    @Test("A studied card shows when it is due and its reviews, newest first")
    func studiedCard() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let card = try await store.addBasicCard(front: "perro", back: "dog", inDeck: spanish)
            try await store.answerNextCard(inDeck: spanish, rating: .again)
            try await store.answerNextCard(inDeck: spanish, rating: .good)

            let model = CardDetailModel(store: store, cardID: card)
            await model.refresh()

            let detail = try #require(model.detail)
            guard case .date(let due) = detail.due else {
                Issue.record("Expected a due date, got \(detail.due)")
                return
            }
            // Still in learning: due again within the day.
            #expect(due > Date.now.addingTimeInterval(-60))
            #expect(due < Date.now.addingTimeInterval(24 * 60 * 60))
            #expect(detail.reviewCount == 2)
            #expect(detail.history.map(\.rating) == [.good, .again])
            #expect(detail.history.map(\.kind) == [.learning, .learning])
            #expect(detail.history.allSatisfy { Calendar.current.isDateInToday($0.date) })
        }
    }

    @Test("A suspended card says so, and the detail follows changes made elsewhere")
    func followsChanges() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let card = try await store.addBasicCard(front: "perro", back: "dog", inDeck: spanish)
            let model = CardDetailModel(store: store, cardID: card)
            let shown = Task { await model.run() }
            defer { shown.cancel() }
            try await eventually("the card shown") { model.detail?.status == .normal }

            try await store.suspend([card])
            try await eventually("the card shown as suspended") { model.detail?.status == .suspended }

            try await store.modify(.removeNotes(.with { $0.cardIds = [card] }))
            try await eventually("the card shown as deleted") { model.state == .deleted }
        }
    }
}

extension CardDetailModel {
    var detail: CardDetail? {
        if case .loaded(let detail) = state { detail } else { nil }
    }
}

extension CardDetailModelTests {
    @Test("Card info includes the deck preset, identifiers, review dates and timing")
    func schedulingDetails() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Languages")
            let id = try await store.addBasicCard(front: "correr", back: "run", inDeck: deck)
            try await store.answerNextCard(inDeck: deck, rating: .easy)

            let model = CardDetailModel(store: store, cardID: id)
            await model.refresh()
            let detail = try #require(model.detail)
            let review = try #require(detail.history.first)
            #expect(detail.cardID == id)
            #expect(detail.noteID > 0)
            #expect(detail.preset == "Default")
            #expect(detail.firstReview == review.date)
            #expect(detail.latestReview == review.date)
            #expect(detail.averageSeconds == review.secondsTaken)
            #expect(detail.totalSeconds == review.secondsTaken)
            #expect(review.intervalSeconds > 0)
            #expect(review.previousIntervalSeconds == 0)
        }
    }
}

extension CardDetailModelTests {
    @Test("An FSRS review anchors the card’s retention curve and preserves its original position")
    func retentionCurve() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Languages")
            let id = try await store.addBasicCard(front: "correr", back: "run", inDeck: deck)
            try await store.modify(.setConfigJson(.with {
                $0.key = "fsrs"
                $0.valueJson = Data("true".utf8)
            }))
            try await store.review(id, rating: .easy, seconds: 7)
            let model = CardDetailModel(store: store, cardID: id)
            await model.refresh()
            let detail = try #require(model.detail)
            let review = try #require(detail.history.first)
            let stability = try #require(review.memoryState?.stabilityDays)
            let oneStabilityFromReview = review.date.addingTimeInterval(stability * 86_400)
            let points = detail.retentionPoints(at: oneStabilityFromReview)
            #expect(detail.originalPosition == 1)
            #expect(detail.totalSeconds == 7)
            #expect(points.first?.probability == 1)
            #expect(points.last?.date == oneStabilityFromReview)
            #expect(abs((points.last?.probability ?? 0) - 0.9) < 0.000001)
        }
    }
}
