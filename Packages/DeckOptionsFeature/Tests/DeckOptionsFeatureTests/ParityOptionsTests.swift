import AnkiProto
import CollectionStore
import CollectionTesting
import DeckOptionsFeature
import Foundation
import Testing

@MainActor
@Suite("Deck options: parity sections", .timeLimit(.minutes(1)))
struct ParityOptionsTests {
    @Test("Daily limits keep separate shared, deck-only, and today-only values")
    func preservesScopedLimits() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "French")
            let neighbor = try await store.addDeck(named: "Spanish")
            let model = await openOptions(store, deck: deck)
            model.newCardsPerDay = 30
            model.reviewsPerDay = 270
            model.deckNewCardsLimit = 20
            model.deckReviewsLimit = 170
            model.todayNewCardsLimit = 2
            model.todayReviewsLimit = 7
            model.newCardsIgnoreReviewLimit = true
            model.applyAllParentLimits = true
            #expect(await model.save())

            let saved = try await store.core.getDeckConfigsForUpdate(.with { $0.did = deck })
            let limits = saved.currentDeck.limits
            #expect(limits.hasNew && limits.new == 20)
            #expect(limits.hasReview && limits.review == 170)
            #expect(limits.newTodayActive && limits.newToday == 2)
            #expect(limits.reviewTodayActive && limits.reviewToday == 7)
            #expect(saved.newCardsIgnoreReviewLimit && saved.applyAllParentLimits)

            let other = await openOptions(store, deck: neighbor)
            #expect(other.newCardsPerDay == 30 && other.reviewsPerDay == 270)
            #expect(other.deckNewCardsLimit == nil && other.deckReviewsLimit == nil)
            #expect(other.todayNewCardsLimit == nil && other.todayReviewsLimit == nil)

            let edited = await openOptions(store, deck: deck)
            edited.todayNewCardsLimit = nil
            edited.deckReviewsLimit = nil
            #expect(await edited.save())
            let reopened = await openOptions(store, deck: deck)
            #expect(reopened.todayNewCardsLimit == nil && reopened.deckReviewsLimit == nil)
            #expect(reopened.deckNewCardsLimit == 20 && reopened.todayReviewsLimit == 7)
        }
    }
}
