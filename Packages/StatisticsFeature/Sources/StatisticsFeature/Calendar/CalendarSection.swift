import SwiftUI

struct CalendarSection: View {
    let graphs: StatisticsGraphs
    @Environment(\.statisticsReportPeriod) private var reportPeriod
    @Environment(\.locale) private var locale
    @Binding var firstWeekday: StatisticsWeekday
    @State private var selectedYear: Int?
    @State private var selectedDay: Date?

    private var calendar: Calendar {
        var calendar = Calendar.statisticsCalendar
        calendar.locale = locale
        return calendar
    }
    private var latestYear: Int { calendar.component(.year, from: graphs.studyDate) }
    private var earliestDate: Date {
        if graphs.period == .allTime {
            return calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? graphs.studyDate
        }
        return calendar.date(byAdding: .day, value: graphs.period.earliestReviewDay, to: graphs.studyDate)
            ?? graphs.studyDate
    }
    private var earliestYear: Int { min(calendar.component(.year, from: earliestDate), latestYear) }
    private var year: Int { min(max(selectedYear ?? latestYear, earliestYear), latestYear) }

    var body: some View {
        let counts = Dictionary(uniqueKeysWithValues: graphs.activityDays().map { ($0.date, $0.count) })
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
                Picker(selection: $firstWeekday) {
                    ForEach(StatisticsWeekday.allCases, id: \.self) { day in
                        Text(calendar.weekdaySymbols[day.rawValue - 1]).tag(day)
                    }
                } label: {
                    Text("First Day of the Week", bundle: .module)
                }

            }

            if counts.isEmpty {
                Text("There are no reviews in this period.", bundle: .module)
                    .foregroundStyle(.secondary)
            } else {
                heatmap(counts: counts)
                if let selection = selectedDay {
                    LabeledContent {
                        reviewCount(counts[selection] ?? 0)
                    } label: {
                        Text(selection, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    }
                }
            }
        } header: {
            Text("Calendar", bundle: .module)
        }
        .onChange(of: year) { selectedDay = nil }
        .onChange(of: graphs.period) { selectedDay = nil }
    }

    private func heatmap(counts: [Date: Int]) -> some View {
        let exporting = reportPeriod != nil
        let size: CGFloat = exporting ? 7 : 15
        let spacing: CGFloat = exporting ? 2 : 3
        let rows = Array(repeating: GridItem(.fixed(size), spacing: spacing), count: 7)
        let days = calendarDays
        let offset = days.first.map { (calendar.component(.weekday, from: $0) - firstWeekday.rawValue + 7) % 7 } ?? 0
        let maxCount = max(1, counts.values.max() ?? 0)
        let grid = LazyHGrid(rows: rows, spacing: spacing) {
            ForEach(0..<offset, id: \.self) { _ in
                Color.clear.frame(width: size, height: size).accessibilityHidden(true)
            }
            ForEach(days, id: \.self) { date in
                let count = counts[date] ?? 0
                let cell = RoundedRectangle(cornerRadius: 2)
                    .fill(count == 0 ? Color.secondary.opacity(0.22) :
                        Color.blue.opacity(0.35 + 0.65 * sqrt(Double(count) / Double(maxCount))))
                    .frame(width: size, height: size)
                if exporting {
                    cell
                } else {
                    Button {
                        selectedDay = date
                    } label: {
                        cell.overlay {
                            if selectedDay == date {
                                RoundedRectangle(cornerRadius: 2).strokeBorder(.primary, lineWidth: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).month(.wide).day().year()))
                    .accessibilityValue(reviewCount(count))
                }
            }
        }
        return HStack(alignment: .top, spacing: 8) {
            if exporting {
                grid
            } else {
                VStack(alignment: .trailing, spacing: spacing) {
                    ForEach(0..<7) { index in
                        Text(calendar.shortWeekdaySymbols[(firstWeekday.rawValue - 1 + index) % 7])
                            .font(.caption2)
                            .frame(height: size)
                    }
                }
                .accessibilityHidden(true)
                ScrollView(.horizontal) {
                    grid
                }
                .defaultScrollAnchor(.trailing)
            }
        }
    }

    private var calendarDays: [Date] {
        guard let january = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let followingYear = calendar.date(byAdding: .year, value: 1, to: january) else { return [] }
        let first = max(january, calendar.startOfDay(for: earliestDate))
        let last = min(followingYear, calendar.startOfDay(for: graphs.studyDate))
        return (0...366).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: first).flatMap {
                $0 <= last && $0 < followingYear ? $0 : nil
            }
        }
    }

    private func reviewCount(_ count: Int) -> Text {
        Text("\(count) reviews", bundle: .module)
    }
}
