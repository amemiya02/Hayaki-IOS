/// How many days in a row the learner has reviewed cards.
public struct StudyStreak: Equatable, Sendable {
    /// Consecutive study days with reviews, ending today, or yesterday when
    /// nothing has been studied yet today (the streak is not broken until the
    /// day ends).
    public let days: Int
    /// True when the streak reaches back to the start of the loaded period,
    /// so it may be longer than `days`.
    public let isAtLeast: Bool

    public init(days: Int, isAtLeast: Bool) {
        self.days = days
        self.isAtLeast = isAtLeast
    }
}

extension StatisticsGraphs {
    /// The current study streak, from the review history the core returned.
    public var studyStreak: StudyStreak {
        let counts = response.reviews.count
        func studied(_ day: Int) -> Bool {
            guard let reviews = counts[Int32(day)] else { return false }
            return reviews.learn + reviews.relearn + reviews.young + reviews.mature + reviews.filtered > 0
        }
        let earliest = period.earliestReviewDay
        var day = studied(0) ? 0 : -1
        var days = 0
        while day >= earliest, studied(day) {
            days += 1
            day -= 1
        }
        return StudyStreak(days: days, isAtLeast: period != .allTime && days > 0 && day < earliest)
    }
}
