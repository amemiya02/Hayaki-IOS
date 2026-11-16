import AnkiProto

/// What the learner studied today, in the chosen deck or the whole collection.
public struct TodaySummary: Equatable, Sendable {
    /// Reviews done today.
    public let reviews: Int
    /// Time spent on today's reviews.
    public let time: Duration
    /// Reviews rated Again.
    public let againCount: Int
    /// Today's reviews by the kind of card reviewed.
    public let learningReviews: Int
    public let reviewReviews: Int
    public let relearningReviews: Int
    /// Reviews of cards in a filtered deck before they were due.
    public let filteredReviews: Int
    /// Reviews of mature cards, and how many of them were not rated Again.
    public let matureReviews: Int
    public let matureCorrect: Int

    public var isEmpty: Bool { reviews == 0 }

    /// The share of today's reviews not rated Again, from 0 to 1.
    public var correctFraction: Double? {
        reviews == 0 ? nil : Double(reviews - againCount) / Double(reviews)
    }

    /// The share of today's mature-card reviews not rated Again, from 0 to 1.
    public var matureCorrectFraction: Double? {
        matureReviews == 0 ? nil : Double(matureCorrect) / Double(matureReviews)
    }

    /// The average time spent on one review.
    public var averageTime: Duration? {
        reviews == 0 ? nil : time / reviews
    }

    init(_ today: Anki_Stats_GraphsResponse.Today) {
        reviews = Int(today.answerCount)
        time = .milliseconds(Int(today.answerMillis))
        againCount = Int(today.answerCount) - Int(today.correctCount)
        learningReviews = Int(today.learnCount)
        reviewReviews = Int(today.reviewCount)
        relearningReviews = Int(today.relearnCount)
        filteredReviews = Int(today.earlyReviewCount)
        matureReviews = Int(today.matureCount)
        matureCorrect = Int(today.matureCorrect)
    }
}

extension StatisticsGraphs {
    /// The values behind the summary of today's studying.
    public var today: TodaySummary {
        TodaySummary(response.today)
    }
}
