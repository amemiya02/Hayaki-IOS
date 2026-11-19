import Foundation

public struct CalendarActivityDay: Identifiable, Equatable, Sendable {
    public let date: Date
    public let count: Int
    public var id: Date { date }
}

extension StatisticsGraphs {
    /// Days with review history, mapped to calendar days from the core's
    /// current study day so activity before rollover stays on the prior day.
    public func activityDays(calendar: Calendar = .statisticsCalendar) -> [CalendarActivityDay] {
        reviewDays.compactMap { review in
            calendar.date(byAdding: .day, value: review.offset, to: calendar.startOfDay(for: studyDate))
                .map { CalendarActivityDay(date: $0, count: review.count) }
        }
    }
}

extension Calendar {
    public static var statisticsCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }
}


// Foundation's weekday indices are one-based, with Sunday first.
enum StatisticsWeekday: Int, CaseIterable {
    case sunday = 1, monday = 2, friday = 6, saturday = 7
}
