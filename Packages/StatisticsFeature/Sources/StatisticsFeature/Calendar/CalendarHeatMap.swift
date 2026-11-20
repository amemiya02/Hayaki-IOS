import Foundation

/// One year of review activity laid out as a calendar heat map: a column per
/// week and a row per weekday, starting from the learner's first day of the week.
public struct CalendarHeatMap: Equatable, Sendable {
    public struct Cell: Identifiable, Equatable, Sendable {
        public let date: Date
        /// The column, counted from the week that holds the first day shown.
        public let week: Int
        /// The row, counted from the first day of the week.
        public let weekday: Int
        public let count: Int
        public var id: Date { date }
    }

    /// The days shown, in order: the year's days from `earliest` to `latest`.
    public let cells: [Cell]
    public var weekCount: Int { (cells.last?.week ?? -1) + 1 }
    public var maxCount: Int { cells.map(\.count).max() ?? 0 }
    public var totalReviews: Int { cells.reduce(0) { $0 + $1.count } }
    public var daysStudied: Int { cells.count { $0.count > 0 } }

    public init(
        activity: [CalendarActivityDay],
        year: Int,
        firstWeekday: StatisticsWeekday,
        earliest: Date,
        latest: Date,
        calendar: Calendar
    ) {
        guard let january = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let followingYear = calendar.date(byAdding: .year, value: 1, to: january) else {
            cells = []
            return
        }
        let counts = Dictionary(activity.map { (calendar.startOfDay(for: $0.date), $0.count) }, uniquingKeysWith: +)
        let first = max(january, calendar.startOfDay(for: earliest))
        let last = min(followingYear, calendar.startOfDay(for: latest))
        let leading = (calendar.component(.weekday, from: first) - firstWeekday.rawValue + 7) % 7
        var cells: [Cell] = []
        var date = first
        while date <= last, date < followingYear {
            let slot = leading + cells.count
            cells.append(Cell(date: date, week: slot / 7, weekday: slot % 7, count: counts[date] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        self.cells = cells
    }

    /// The day at a position on the map, such as where a finger is.
    public func cell(week: Int, weekday: Int) -> Cell? {
        cells.first { $0.week == week && $0.weekday == weekday }
    }
}

extension StatisticsGraphs {
    /// The first calendar day the period covers.
    public func earliestCalendarDate(calendar: Calendar = .statisticsCalendar) -> Date {
        if period == .allTime {
            return calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? studyDate
        }
        return calendar.date(byAdding: .day, value: period.earliestReviewDay, to: studyDate) ?? studyDate
    }

    /// One year of the period's review activity as a heat map.
    public func calendarHeatMap(
        year: Int,
        firstWeekday: StatisticsWeekday,
        calendar: Calendar = .statisticsCalendar
    ) -> CalendarHeatMap {
        CalendarHeatMap(
            activity: activityDays(calendar: calendar),
            year: year,
            firstWeekday: firstWeekday,
            earliest: earliestCalendarDate(calendar: calendar),
            latest: studyDate,
            calendar: calendar
        )
    }
}
