import CollectionTesting
import Foundation
import PDFKit
@testable import StatisticsFeature
import SwiftUI
import Testing

@MainActor
@Suite("Statistics PDF")
struct StatisticsPDFTests {
    @Test("The native report contains sections for the selected deck and period")
    func exportsSelectedDeckReport() async throws {
        try await withTemporaryCollection { store in
            let selected = try await store.addDeck(named: "Report Deck")
            let other = try await store.addDeck(named: "Other Deck")
            let cards = try await store.addBasicNotes(count: 2, toDeck: selected)
            try await store.makeReviewCardsDueToday(cards, intervalDays: 40)
            try await store.review(cards[0], rating: .good, daysAgo: 42, seconds: 11)
            try await store.addBasicNotes(count: 3, toDeck: other)

            let model = StatisticsModel(store: store)
            model.scope = .deck(id: selected)
            model.period = .allTime
            await model.refresh()
            let graphs = try #require(model.graphs)

            let report = try StatisticsPDF.make(
                graphs: graphs, preferences: model.preferences, scope: Text("Report Deck"),
                locale: Locale(identifier: "en")
            )
            let document = try #require(PDFDocument(data: report.data))
            #expect(document.pageCount >= 10)

            let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined()
            #expect(text.contains("Report Deck"))
            #expect(!text.contains("Other Deck"))
            #expect(text.contains("Card Counts"))
            #expect(text.contains("True Retention"))
            #expect(text.contains("Review Time"))
            let timePage = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
                .first { $0.contains("Average Answer Time") }
            #expect(timePage?.contains("11.0") == true)
        }
    }
}
