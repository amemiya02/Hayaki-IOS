import CollectionTesting
import Foundation
@testable import DeckOptionsFeature
import Testing

@MainActor
@Suite("FSRS inline estimates")
struct FSRSInlineEstimatesTests {
    @Test("The cutoff hint uses the preset's actual included card count")
    func cutoffEstimate() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "History Cutoff")
            let cards = try await store.addBasicNotes(count: 2, toDeck: deck)
            try await store.review(cards[0], rating: .good, daysAgo: 10, seconds: 3)
            try await store.review(cards[1], rating: .good, daysAgo: 1, seconds: 3)

            let model = DeckOptionsModel(store: store, deckID: deck)
            await model.load()
            #expect(model.fsrsCutoffEstimateRequest == nil)
            model.ignoreFSRSHistoryBefore = Calendar.current.date(byAdding: .day, value: -5, to: .now)
            let request = try #require(model.fsrsCutoffEstimateRequest)
            let estimate = await model.loadFSRSCutoffEstimate(request)
            #expect(estimate?.included == 1)
            #expect(estimate?.total == 2)
        }
    }

    @Test("Comparing retention uses both core costs and rejects missing or zero baseline cost")
    func workloadRatio() {
        let workload = DeckOptionsModel.FSRSWorkloadEstimateRequest(
            search: "preset:Default", parameters: [], previous: 90, target: 95
        )
        #expect(workload.ratio(in: [90: 2, 95: 3]) == 1.5)
        #expect(workload.ratio(in: [90: 0, 95: 3]) == nil)
        #expect(workload.ratio(in: [90: 2]) == nil)
    }
}
