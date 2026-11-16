import AnkiProto

/// The learner's judgement of a review.
public enum Rating: Int, CaseIterable, Hashable, Sendable {
    case again = 1
    case hard
    case good
    case easy

    public var title: String {
        switch self {
        case .again: String(localized: "Again", bundle: .module, comment: "Rating: the card was forgotten.")
        case .hard: String(localized: "Hard", bundle: .module, comment: "Rating: recalled with difficulty.")
        case .good: String(localized: "Good", bundle: .module, comment: "Rating: recalled.")
        case .easy: String(localized: "Easy", bundle: .module, comment: "Rating: recalled easily.")
        }
    }
}

/// What kind of card was reviewed, as the ratings chart groups reviews.
public enum ReviewedCardKind: CaseIterable, Hashable, Sendable {
    /// A card being learnt or relearnt.
    case learning
    /// A review card with an interval under 21 days.
    case young
    /// A review card with an interval of 21 days or more.
    case mature

    public var title: String {
        switch self {
        case .learning: String(localized: "Learning", bundle: .module, comment: "Card state: being learnt or relearnt.")
        case .young: String(localized: "Young", bundle: .module, comment: "Card state: in review with an interval under 21 days.")
        case .mature: String(localized: "Mature", bundle: .module, comment: "Card state: in review with an interval of 21 days or more.")
        }
    }
}

/// How often the learner chose each rating during the chosen period, split by
/// the kind of card reviewed.
public struct RatingCounts: Equatable, Sendable {
    public struct Entry: Identifiable, Equatable, Sendable {
        public let kind: ReviewedCardKind
        public let rating: Rating
        public let count: Int
        public var id: String { "\(kind)-\(rating)" }
    }

    /// One entry per kind of card and rating, including empty ones.
    public let entries: [Entry]

    public var total: Int { entries.reduce(0) { $0 + $1.count } }
    public var isEmpty: Bool { total == 0 }

    /// How often `rating` was chosen, over every kind of card.
    public func count(_ rating: Rating) -> Int {
        entries.filter { $0.rating == rating }.reduce(0) { $0 + $1.count }
    }

    /// The share of all reviews rated `rating`, from 0 to 1.
    public func fraction(_ rating: Rating) -> Double {
        isEmpty ? 0 : Double(count(rating)) / Double(total)
    }

    /// How often `rating` was chosen for one kind of card.
    public func count(_ rating: Rating, for kind: ReviewedCardKind) -> Int {
        entries.first { $0.kind == kind && $0.rating == rating }?.count ?? 0
    }

    /// Reviews of one kind of card.
    public func reviews(of kind: ReviewedCardKind) -> Int {
        entries.filter { $0.kind == kind }.reduce(0) { $0 + $1.count }
    }

    /// The share of reviews of one kind of card not rated Again, from 0 to 1;
    /// nil when there were none.
    public func correctFraction(of kind: ReviewedCardKind) -> Double? {
        let reviews = reviews(of: kind)
        guard reviews > 0 else { return nil }
        return Double(reviews - count(.again, for: kind)) / Double(reviews)
    }

    init(_ buttons: Anki_Stats_GraphsResponse.Buttons, period: StatisticsPeriod) {
        let counts = switch period {
        case .month: buttons.oneMonth
        case .threeMonths: buttons.threeMonths
        case .year: buttons.oneYear
        case .allTime: buttons.allTime
        }
        entries = ReviewedCardKind.allCases.flatMap { kind in
            // One count per rating, Again first.
            let perRating = switch kind {
            case .learning: counts.learning
            case .young: counts.young
            case .mature: counts.mature
            }
            return Rating.allCases.map { rating in
                let index = rating.rawValue - 1
                let count = perRating.indices.contains(index) ? Int(perRating[index]) : 0
                return Entry(kind: kind, rating: rating, count: count)
            }
        }
    }
}

extension StatisticsGraphs {
    /// The values behind the ratings chart, for the chosen period.
    public var ratings: RatingCounts {
        RatingCounts(response.buttons, period: period)
    }
}
