import Foundation
import StatisticsFeature
import Testing

@Suite("Calendar heat map")
struct CalendarHeatMapTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test("Every day of the year up to today gets a cell, with that day's review count")
    func cellsMatchReviewCounts() {
        let today = day(2026, 3, 4)
        let map = CalendarHeatMap(
            activity: [
                CalendarActivityDay(date: day(2025, 12, 31), count: 9),
                CalendarActivityDay(date: day(2026, 1, 1), count: 4),
                CalendarActivityDay(date: day(2026, 2, 10), count: 12),
                CalendarActivityDay(date: today, count: 3),
            ],
            year: 2026, firstWeekday: .sunday, earliest: day(2025, 3, 5), latest: today, calendar: calendar
        )

        // 31 days of January, 28 of February and 4 of March.
        #expect(map.cells.count == 63)
        #expect(map.cells.first?.date == day(2026, 1, 1))
        #expect(map.cells.last?.date == today)
        #expect(map.cells.filter { $0.count > 0 }.map(\.count) == [4, 12, 3])
        #expect(map.cells.first { $0.date == day(2026, 2, 10) }?.count == 12)
        #expect(map.totalReviews == 19)
        #expect(map.daysStudied == 3)
        #expect(map.maxCount == 12)
    }

    @Test("Cells fill weekday rows from the chosen first day of the week, one column per week")
    func weekLayout() {
        // 1 January 2026 is a Thursday.
        let latest = day(2026, 1, 12)
        let sunday = CalendarHeatMap(
            activity: [], year: 2026, firstWeekday: .sunday,
            earliest: day(2025, 1, 1), latest: latest, calendar: calendar
        )
        #expect(sunday.cells.first.map { [$0.week, $0.weekday] } == [0, 4])
        // Sunday 4 January starts the second column.
        #expect(sunday.cells.first { $0.date == day(2026, 1, 4) }.map { [$0.week, $0.weekday] } == [1, 0])
        #expect(sunday.weekCount == 3)

        let monday = CalendarHeatMap(
            activity: [], year: 2026, firstWeekday: .monday,
            earliest: day(2025, 1, 1), latest: latest, calendar: calendar
        )
        #expect(monday.cells.first.map { [$0.week, $0.weekday] } == [0, 3])
        #expect(monday.cells.first { $0.date == day(2026, 1, 4) }.map { [$0.week, $0.weekday] } == [0, 6])
        #expect(monday.cells.first { $0.date == day(2026, 1, 5) }.map { [$0.week, $0.weekday] } == [1, 0])
    }

    @Test("A period that starts inside the year leaves out the days before it")
    func periodStart() {
        let today = day(2026, 3, 4)
        let map = CalendarHeatMap(
            activity: [CalendarActivityDay(date: day(2026, 1, 20), count: 2)],
            year: 2026, firstWeekday: .sunday, earliest: day(2026, 2, 3), latest: today, calendar: calendar
        )
        #expect(map.cells.first?.date == day(2026, 2, 3))
        #expect(map.totalReviews == 0)
    }

    @Test("Looking up a scrubbed position finds the cell in that week and weekday")
    func cellLookup() {
        let map = CalendarHeatMap(
            activity: [CalendarActivityDay(date: day(2026, 1, 6), count: 5)],
            year: 2026, firstWeekday: .sunday, earliest: day(2025, 1, 1), latest: day(2026, 1, 12), calendar: calendar
        )
        // Tuesday 6 January: second column, third row.
        #expect(map.cell(week: 1, weekday: 2)?.count == 5)
        #expect(map.cell(week: 0, weekday: 0) == nil)
    }
}

@Suite("Daily chart scrolling")
struct DailyChartScrollingTests {
    @Test("A month or three months fit on screen, a year scrolls 92 days at a time")
    func visibleLength() {
        #expect(DailyChartScrolling.visibleLength(for: -30...0) == nil)
        #expect(DailyChartScrolling.visibleLength(for: 0...90) == nil)
        #expect(DailyChartScrolling.visibleLength(for: -89...1) == nil)
        #expect(DailyChartScrolling.visibleLength(for: 0...365) == 92)
        #expect(DailyChartScrolling.visibleLength(for: -364...0) == 92)
        // Review history opens on its last 92 days, today included.
        #expect(DailyChartScrolling.firstVisibleDay(endingAt: 0) == -91)
    }
}
