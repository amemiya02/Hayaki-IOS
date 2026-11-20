import AnkiProto
import Foundation
import HayakiAppearance
import SwiftUI

public enum StatisticsReviewKind: CaseIterable, Sendable {
    case learning, relearning, young, mature, filtered

    var title: String {
        switch self {
        case .learning: String(localized: "Learning", bundle: .module)
        case .relearning: String(localized: "Relearning", bundle: .module)
        case .young: String(localized: "Young", bundle: .module)
        case .mature: String(localized: "Mature", bundle: .module)
        case .filtered: String(localized: "Filtered", bundle: .module)
        }
    }

    /// The count colors from the design tokens: learning reviews in the
    /// Learning red, reviews of graduated cards in the Due green, with the
    /// lighter shade for relearning and young cards. Filtered-deck reviews
    /// carry no count meaning, so they are gray.
    var color: Color {
        switch self {
        case .learning: SemanticColor.learning.color
        case .relearning: SemanticColor.learning.color.opacity(0.5)
        case .young: SemanticColor.due.color.opacity(0.5)
        case .mature: SemanticColor.due.color
        case .filtered: .gray
        }
    }

    fileprivate func value(in reviews: Anki_Stats_GraphsResponse.ReviewCountsAndTimes.Reviews) -> Int {
        switch self {
        case .learning: Int(reviews.learn)
        case .relearning: Int(reviews.relearn)
        case .young: Int(reviews.young)
        case .mature: Int(reviews.mature)
        case .filtered: Int(reviews.filtered)
        }
    }
}

public struct ReviewDay: Identifiable, Equatable, Sendable {
    public struct Entry: Identifiable, Equatable, Sendable {
        public let kind: StatisticsReviewKind
        public let count: Int
        public let milliseconds: Int
        public var id: StatisticsReviewKind { kind }
    }

    /// The study day relative to today (zero).
    public let offset: Int
    public let entries: [Entry]
    public var id: Int { offset }
    public var count: Int { entries.reduce(0) { $0 + $1.count } }
    public var milliseconds: Int { entries.reduce(0) { $0 + $1.milliseconds } }
}

extension StatisticsGraphs {
    public var reviewDays: [ReviewDay] {
        let reviews = response.reviews
        let earliest = period.earliestReviewDay
        return reviews.count.keys.sorted().compactMap { day in
            guard earliest...0 ~= Int(day), let count = reviews.count[day] else { return nil }
            let time = reviews.time[day] ?? .init()
            let entries = StatisticsReviewKind.allCases.map { kind in
                ReviewDay.Entry(kind: kind, count: kind.value(in: count), milliseconds: kind.value(in: time))
            }
            return ReviewDay(offset: Int(day), entries: entries)
        }
    }
}

extension StatisticsPeriod {
    // Matches the inclusive left edge of the pinned Reviews graph. The
    // core reads an extra day so local graph ranges can select this edge.
    var earliestReviewDay: Int {
        switch self {
        case .month: -30
        case .threeMonths: -89
        case .year: -364
        case .allTime: Int.min
        }
    }

    var latestForecastDay: Int {
        switch self {
        case .month: 31
        case .threeMonths: 90
        case .year: 365
        case .allTime: Int.max
        }
    }
}
