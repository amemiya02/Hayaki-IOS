import AnkiProto
import Foundation

public struct CardDistribution: Equatable, Sendable {
    public enum Kind: Hashable, Sendable {
        case intervals, ease, stability, difficulty, retrievability

        var title: String {
            switch self {
            case .intervals: String(localized: "Review Intervals", bundle: .module)
            case .ease: String(localized: "Card Ease", bundle: .module)
            case .stability: String(localized: "Card Stability", bundle: .module)
            case .difficulty: String(localized: "Card Difficulty", bundle: .module)
            case .retrievability: String(localized: "Card Retrievability", bundle: .module)
            }
        }

        var usesDays: Bool { self == .intervals || self == .stability }
        var usesPercentageRange: Bool { self == .difficulty || self == .retrievability }
    }

    public struct Bucket: Identifiable, Equatable, Sendable {
        public let value: Int
        public let count: Int
        public var id: Int { value }
    }

    public let kind: Kind
    public let buckets: [Bucket]
    /// Median for interval, ease, stability and difficulty; mean for retrievability.
    /// Units are days for intervals and stability and percentage points otherwise.
    public let typicalValue: Double
    public let estimatedRememberedCards: Double?
    public let estimatedRememberedNotes: Double?
    public var total: Int { buckets.reduce(0) { $0 + $1.count } }

    init(
        kind: Kind,
        counts: [UInt32: UInt32],
        typicalValue: Double? = nil,
        estimatedRememberedCards: Double? = nil,
        estimatedRememberedNotes: Double? = nil
    ) {
        let buckets = counts.map { Bucket(value: Int($0.key), count: Int($0.value)) }
            .filter { $0.count > 0 }
            .sorted { $0.value < $1.value }
        self.kind = kind
        self.buckets = buckets
        self.typicalValue = typicalValue ?? Self.quantile(of: buckets, fraction: 0.5)
        self.estimatedRememberedCards = estimatedRememberedCards
        self.estimatedRememberedNotes = estimatedRememberedNotes
    }

    func quantile(_ fraction: Double) -> Double {
        Self.quantile(of: buckets, fraction: fraction)
    }

    private static func quantile(of buckets: [Bucket], fraction: Double) -> Double {
        let total = buckets.reduce(0) { $0 + $1.count }
        guard total > 0 else { return 0 }
        let rank = Double(total - 1) * fraction
        let lowerIndex = Int(rank.rounded(.down))
        let upperIndex = Int(rank.rounded(.up))
        var lowerValue = 0
        var end = 0
        for bucket in buckets {
            if end <= lowerIndex && lowerIndex < end + bucket.count {
                lowerValue = bucket.value
            }
            end += bucket.count
            if upperIndex < end {
                return Double(lowerValue) + Double(bucket.value - lowerValue) * (rank - Double(lowerIndex))
            }
        }
        return Double(lowerValue)
    }

    /// Weighted, discrete percentiles for the core's whole-percentage buckets.
    func percentageQuantile(_ fraction: Double) -> Int {
        var remaining = Double(total) * fraction
        for bucket in buckets {
            remaining -= Double(bucket.count)
            if remaining <= 0 { return bucket.value }
        }
        return buckets.last?.value ?? 0
    }
}

extension StatisticsGraphs {
    public var distributions: [CardDistribution] {
        let intervals = CardDistribution(kind: .intervals, counts: response.intervals.intervals)
        if response.fsrs {
            return [
                intervals,
                CardDistribution(kind: .stability, counts: response.stability.intervals),
                CardDistribution(
                    kind: .difficulty,
                    counts: response.difficulty.eases,
                    typicalValue: Double(response.difficulty.average)
                ),
                CardDistribution(
                    kind: .retrievability,
                    counts: response.retrievability.retrievability,
                    typicalValue: Double(response.retrievability.average),
                    estimatedRememberedCards: Double(response.retrievability.sumByCard),
                    estimatedRememberedNotes: Double(response.retrievability.sumByNote)
                )
            ]
        }

        return [
            intervals,
            CardDistribution(kind: .ease, counts: response.eases.eases, typicalValue: Double(response.eases.average))
        ]
    }
}
