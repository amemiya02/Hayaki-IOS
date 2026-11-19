import Foundation

/// Which cards the statistics cover.
public enum StatisticsScope: Hashable, Sendable {
    case collection
    case deck(id: Int64)
    case search(String)
}

/// How far back the statistics look at the learner's review history.
///
/// Charts of the collection as it is now (today's studying, card counts) do
/// not depend on it; charts of past reviews (ratings) do.
public enum StatisticsPeriod: CaseIterable, Hashable, Sendable {
    case month
    case threeMonths
    case year
    case allTime

    /// The number of days of review history the core reads; 0 reads all of it.
    var days: UInt32 {
        switch self {
        case .month: 30
        case .threeMonths: 90
        case .year: 365
        case .allTime: 0
        }
    }

    /// The period's name in the period picker.
    public var title: String {
        switch self {
        case .month: String(localized: "1 Month", bundle: .module, comment: "Statistics period: the last month.")
        case .threeMonths: String(localized: "3 Months", bundle: .module, comment: "Statistics period: the last three months.")
        case .year: String(localized: "1 Year", bundle: .module, comment: "Statistics period: the last year.")
        case .allTime: String(localized: "All Time", bundle: .module, comment: "Statistics period: the whole review history.")
        }
    }
}

/// A deck the learner can choose to see statistics for.
public struct StatisticsDeck: Identifiable, Hashable, Sendable {
    public let id: Int64
    /// The deck's full name, such as `"Languages::Japanese"`.
    public let fullName: String

    /// The deck's name with its parents, as shown in the deck picker, such as
    /// "Languages › Japanese".
    public var displayName: String {
        fullName.replacing("::", with: " › ")
    }
}
