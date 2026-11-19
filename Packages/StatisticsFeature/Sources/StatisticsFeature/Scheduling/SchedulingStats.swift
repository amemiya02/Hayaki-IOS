import AnkiProto
import Foundation

public struct HourlyReviews: Identifiable, Equatable, Sendable {
    public let hour: Int
    public let count: Int
    public let correct: Int
    public var id: Int { hour }
    public var successRate: Double? { count > 0 ? Double(correct) / Double(count) : nil }
}

public struct TrueRetention: Equatable, Sendable {
    public enum Window: CaseIterable, Hashable, Sendable {
        case today, yesterday, week, month, year, allTime

        var title: String {
            switch self {
            case .today: String(localized: "Today", bundle: .module)
            case .yesterday: String(localized: "Yesterday", bundle: .module)
            case .week: String(localized: "Last Week", bundle: .module)
            case .month: String(localized: "Last Month", bundle: .module)
            case .year: String(localized: "Last Year", bundle: .module)
            case .allTime: String(localized: "All Time", bundle: .module)
            }
        }
    }

    public struct Result: Equatable, Sendable {
        public let passed: Int
        public let failed: Int
        public var total: Int { passed + failed }
        public var rate: Double? { total > 0 ? Double(passed) / Double(total) : nil }
    }

    public let window: Window
    public let young: Result
    public let mature: Result
    public var combined: Result {
        Result(passed: young.passed + mature.passed, failed: young.failed + mature.failed)
    }
}

extension StatisticsGraphs {
    public var hourlyReviews: [HourlyReviews] {
        let hours = response.hours
        let buckets = switch period {
        case .month: hours.oneMonth
        case .threeMonths: hours.threeMonths
        case .year: hours.oneYear
        case .allTime: hours.allTime
        }
        return buckets.enumerated().map { hour, bucket in
            HourlyReviews(hour: hour, count: Int(bucket.total), correct: Int(bucket.correct))
        }
    }

    public var trueRetention: [TrueRetention] {
        let data = response.trueRetention
        let windows = TrueRetention.Window.allCases.filter { window in
            switch window {
            case .year: period == .year || period == .allTime
            case .allTime: period == .allTime
            default: true
            }
        }
        return windows.map { window in
            let value = switch window {
            case .today: data.today
            case .yesterday: data.yesterday
            case .week: data.week
            case .month: data.month
            case .year: data.year
            case .allTime: data.allTime
            }
            return TrueRetention(
                window: window,
                young: TrueRetention.Result(passed: Int(value.youngPassed), failed: Int(value.youngFailed)),
                mature: TrueRetention.Result(passed: Int(value.maturePassed), failed: Int(value.matureFailed))
            )
        }
    }

    public var addedDays: [DailyCardCount] {
        let earliest = period == .allTime ? Int.min : -period.latestForecastDay
        return response.added.added.compactMap { day, count in
            guard earliest...1 ~= Int(day) else { return nil }
            return DailyCardCount(offset: Int(day), count: Int(count))
        }.sorted { $0.offset < $1.offset }
    }
}
