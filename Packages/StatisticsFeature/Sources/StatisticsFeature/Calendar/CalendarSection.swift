import Charts
import HayakiAppearance
import SwiftUI

/// A year of review activity as a Swift Charts heat map: a column per week,
/// a row per weekday, shaded in the theme accent by the number of reviews.
struct CalendarSection: View {
    let graphs: StatisticsGraphs
    @Environment(\.statisticsReportPeriod) private var reportPeriod
    @Environment(\.hayakiTheme) private var theme
    @Environment(\.locale) private var locale
    @Binding var firstWeekday: StatisticsWeekday
    @State private var selectedYear: Int?
    @State private var selectedWeek: Double?
    @State private var selectedRow: Double?

    /// Weeks shown at once before the map scrolls sideways.
    private static let visibleWeeks = 26

    private var calendar: Calendar {
        var calendar = Calendar.statisticsCalendar
        calendar.locale = locale
        return calendar
    }
    private var latestYear: Int { calendar.component(.year, from: graphs.studyDate) }
    private var earliestYear: Int {
        min(calendar.component(.year, from: graphs.earliestCalendarDate(calendar: calendar)), latestYear)
    }
    private var year: Int { min(max(selectedYear ?? latestYear, earliestYear), latestYear) }

    var body: some View {
        let hasActivity = !graphs.activityDays(calendar: calendar).isEmpty
        let map = graphs.calendarHeatMap(year: year, firstWeekday: firstWeekday, calendar: calendar)
        Section {
            if reportPeriod != nil {
                Text(year.formatted(.number.grouping(.never))).monospacedDigit()
            } else {
                HStack {
                    Button {
                        selectedYear = year - 1
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel(Text("Previous Year", bundle: .module))
                    .disabled(year <= earliestYear)
                    Spacer()
                    Text(year.formatted(.number.grouping(.never))).monospacedDigit()
                    Spacer()
                    Button {
                        selectedYear = year + 1
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .accessibilityLabel(Text("Next Year", bundle: .module))
                    .disabled(year >= latestYear)
                }
                .buttonStyle(.borderless)
                LabeledContent {
                    Picker(selection: $firstWeekday) {
                        ForEach(StatisticsWeekday.allCases, id: \.self) { day in
                            Text(calendar.weekdaySymbols[day.rawValue - 1]).tag(day)
                        }
                    } label: {
                        Text("First Day of the Week", bundle: .module)
                    }
                    .labelsHidden()
                } label: {
                    Text("First Day of the Week", bundle: .module)
                }
            }

            if hasActivity {
                heatMap(map)
            } else {
                Text("There are no reviews in this period.", bundle: .module)
                    .foregroundStyle(.secondary)
            }
        } header: {
            StatisticsCardHeader(
                title: Text("Calendar", bundle: .module),
                reading: hasActivity ? Text(
                    "You studied on \(map.daysStudied) days in \(Text(year.formatted(.number.grouping(.never))))",
                    bundle: .module,
                    comment: "Calendar card reading: the number of days with reviews in the year shown, e.g. \"You studied on 120 days in 2026\"."
                ) : nil
            )
        }
        .onChange(of: year) { clearSelection() }
        .onChange(of: graphs.period) { clearSelection() }
        .onChange(of: firstWeekday) { clearSelection() }
    }

    private func clearSelection() {
        selectedWeek = nil
        selectedRow = nil
    }

    private func selectedCell(in map: CalendarHeatMap) -> CalendarHeatMap.Cell? {
        guard let selectedWeek, let selectedRow else { return nil }
        return map.cell(week: Int(selectedWeek.rounded(.down)), weekday: 6 - Int(selectedRow.rounded(.down)))
    }

    private func heatMap(_ map: CalendarHeatMap) -> some View {
        let exporting = reportPeriod != nil
        let weeks = max(map.weekCount, 1)
        let maxCount = max(map.maxCount, 1)
        let selected = exporting ? nil : selectedCell(in: map)
        let monthStarts = map.cells.filter { calendar.component(.day, from: $0.date) == 1 || $0.date == map.cells.first?.date }
        let chart = Chart {
            ForEach(map.cells) { cell in
                cellMark(cell, inset: 0.1)
                    .foregroundStyle(fill(count: cell.count, maxCount: maxCount))
                    .accessibilityLabel(Text(cell.date, format: .dateTime.weekday(.wide).month(.wide).day().year()))
                    .accessibilityValue(reviewCount(cell.count))
            }
            if let selected {
                cellMark(selected, inset: 0)
                    .foregroundStyle(Color.primary.opacity(0.35))
                    .accessibilityHidden(true)
                    .annotation(position: .top, spacing: 4, overflowResolution: calloutOverflow) {
                        ChartCallout(
                            title: Text(selected.date, format: .dateTime.weekday(.wide).month(.abbreviated).day()),
                            value: reviewCount(selected.count)
                        )
                    }
            }
        }
        .chartXScale(domain: 0...Double(weeks))
        .chartYScale(domain: 0...7)
        .chartXAxis {
            AxisMarks(values: monthStarts.map { Double($0.week) }) { value in
                if let week = value.as(Double.self),
                   let start = monthStarts.first(where: { Double($0.week) == week }) {
                    AxisValueLabel(anchor: .topLeading) {
                        Text(start.date, format: .dateTime.month(.abbreviated))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: (0..<7).map { 6.5 - Double($0) }) { value in
                if let position = value.as(Double.self) {
                    AxisValueLabel {
                        Text(calendar.shortWeekdaySymbols[(firstWeekday.rawValue - 1 + Int(6.5 - position)) % 7])
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: exporting ? 90 : 160)

        return Group {
            if exporting || weeks <= Self.visibleWeeks {
                chart
            } else {
                chart
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: Double(Self.visibleWeeks))
                    .chartScrollPosition(initialX: Double(weeks - Self.visibleWeeks))
            }
        }
        .chartXSelection(value: $selectedWeek)
        .chartYSelection(value: $selectedRow)
    }

    private func cellMark(_ cell: CalendarHeatMap.Cell, inset: Double) -> RectangleMark {
        RectangleMark(
            xStart: .value("Week", Double(cell.week) + inset),
            xEnd: .value("Week", Double(cell.week + 1) - inset),
            yStart: .value("Weekday", Double(6 - cell.weekday) + inset),
            yEnd: .value("Weekday", Double(7 - cell.weekday) - inset)
        )
    }

    /// Days without reviews use the system's faint fill; others are the
    /// accent, darker with more reviews.
    private func fill(count: Int, maxCount: Int) -> AnyShapeStyle {
        count == 0
            ? AnyShapeStyle(.fill.quaternary)
            : AnyShapeStyle(theme.accent.opacity(0.3 + 0.7 * sqrt(Double(count) / Double(maxCount))))
    }

    private func reviewCount(_ count: Int) -> Text {
        Text("\(count) reviews", bundle: .module)
    }
}
