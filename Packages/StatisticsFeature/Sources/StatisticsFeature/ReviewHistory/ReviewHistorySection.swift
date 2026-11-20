import Charts
import HayakiAppearance
import SwiftUI

struct ReviewHistorySection: View {
    let graphs: StatisticsGraphs
    @Environment(\.locale) private var locale
    @Environment(\.statisticsReportPeriod) private var reportPeriod
    @Environment(\.hayakiTheme) private var theme
    private var displayedPeriod: StatisticsPeriod { reportPeriod ?? graphs.period }

    var reportReviewTime: Bool? = nil
    @State private var showTime = false
    private var showsTime: Bool { reportReviewTime ?? showTime }
    @State private var showCumulative = false
    @State private var position: Double?
    private var selection: Int? { position.map { Int($0.rounded()) } }

    var body: some View {
        let days = graphs.displaying(displayedPeriod).reviewDays
        let firstDay = displayedPeriod == .allTime ? days.first?.offset ?? 0 : displayedPeriod.earliestReviewDay
        Section {
            if reportPeriod == nil {
                Toggle(isOn: $showTime) { Text("Review Time", bundle: .module) }
            }
            if days.isEmpty {
                Text("There are no reviews in this period.", bundle: .module)
                    .foregroundStyle(.secondary)
            } else {
                if reportPeriod == nil {
                    Toggle(isOn: $showCumulative) { Text("Running Total", bundle: .module) }
                }
                chart(days, firstDay: firstDay)
                summary(days, firstDay: firstDay)
            }
        } header: {
            StatisticsCardHeader(
                title: reportReviewTime == true ? Text("Review Time", bundle: .module) : Text("Reviews", bundle: .module),
                reading: days.isEmpty ? nil : Text(
                    "You studied on \(days.count) of the last \(1 - firstDay) days",
                    bundle: .module,
                    comment: "Reviews card reading: days with reviews, out of the days in the period."
                )
            )
        }
    }

    private func chart(_ days: [ReviewDay], firstDay: Int) -> some View {
        Chart {
            if showCumulative {
                cumulativeMarks(days)
            } else {
                dailyMarks(days)
            }
            if let selection {
                RuleMark(x: .value("Day", Double(selection)))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    .annotation(position: .top, spacing: 4, overflowResolution: calloutOverflow) {
                        callout(days, selection: selection)
                    }
            }
        }
        .chartXScale(domain: (Double(firstDay) - 0.5)...0.5)
        .dailyChartScrolling(
            range: firstDay...0,
            initialDay: DailyChartScrolling.firstVisibleDay(endingAt: 0),
            enabled: reportPeriod == nil
        )
        .chartForegroundStyleScale(
            domain: StatisticsReviewKind.allCases.map(\.title),
            range: StatisticsReviewKind.allCases.map(\.color)
        )
        .chartLegend(showCumulative ? .hidden : .visible)
        .chartXSelection(value: $position)
        .chartYAxisLabel { metric }
        .frame(height: 210)
        .onChange(of: graphs.period) { position = nil }
    }

    @ChartContentBuilder
    private func cumulativeMarks(_ days: [ReviewDay]) -> some ChartContent {
        let totals = days.reduce(into: [Int]()) { values, day in
            values.append((values.last ?? 0) + value(day))
        }
        ForEach(days.indices, id: \.self) { index in
            let day = days[index]
            LineMark(x: .value("Day", Double(day.offset)), y: .value(metric, chartValue(totals[index])))
                .foregroundStyle(theme.accent)
                .accessibilityHidden(true)
            PointMark(x: .value("Day", Double(day.offset)), y: .value(metric, chartValue(totals[index])))
                .foregroundStyle(theme.accent)
                .accessibilityLabel(relativeDay(day.offset))
                .accessibilityValue(valueText(totals[index]))
        }
    }

    @ChartContentBuilder
    private func dailyMarks(_ days: [ReviewDay]) -> some ChartContent {
        ForEach(days) { day in
            ForEach(day.entries.indices, id: \.self) { index in
                let entry = day.entries[index]
                let amount = value(entry)
                let bottom = day.entries.prefix(index).reduce(0) { $0 + value($1) }
                if amount > 0 {
                    RectangleMark(
                        xStart: .value("Day", Double(day.offset) - 0.4),
                        xEnd: .value("Day", Double(day.offset) + 0.4),
                        yStart: .value(metric, chartValue(bottom)),
                        yEnd: .value(metric, chartValue(bottom + amount))
                    )
                    .foregroundStyle(by: .value("Review Type", entry.kind.title))
                    .accessibilityLabel(Text("\(relativeDay(day.offset)), \(entry.kind.title)", bundle: .module))
                    .accessibilityValue(valueText(amount))
                }
            }
        }
    }

    @ViewBuilder
    private func summary(_ days: [ReviewDay], firstDay: Int) -> some View {
        let total = days.reduce(0) { $0 + value($1) }
        let count = days.reduce(0) { $0 + $1.count }
        let numberOfDays = 1 - firstDay
        LabeledContent {
            valueText(total)
        } label: {
            Text("Total", bundle: .module)
        }
        LabeledContent {
            Text("\(days.count.formatted()) / \(numberOfDays.formatted())")
        } label: {
            Text("Days Studied", bundle: .module)
        }
        LabeledContent {
            valueText(Int((Double(total) / Double(days.count)).rounded()))
        } label: {
            Text("Average on Days Studied", bundle: .module)
        }
        LabeledContent {
            valueText(Int((Double(total) / Double(numberOfDays)).rounded()))
        } label: {
            Text("Average over Period", bundle: .module)
        }
        if showsTime, count > 0 {
            LabeledContent {
                valueText(total / count)
            } label: {
                Text("Average Answer Time", bundle: .module)
            }
        }
    }

    private func callout(_ days: [ReviewDay], selection: Int) -> some View {
        let day = days.first { $0.offset == selection }
        let runningTotal = days.lazy.filter { $0.offset <= selection }.reduce(0) { $0 + value($1) }
        let breakdown = (day?.entries ?? [])
            .filter { value($0) > 0 }
            .map { (label: Text($0.kind.title), value: valueText(value($0))) }
        return ChartCallout(
            title: relativeDay(selection),
            value: showCumulative ? valueText(runningTotal) : valueText(day.map { value($0) } ?? 0),
            details: showCumulative ? [] : breakdown + [(Text("Running Total", bundle: .module), valueText(runningTotal))]
        )
    }

    private var metric: Text {
        if showsTime {
            Text("Minutes", bundle: .module)
        } else {
            Text("Reviews", bundle: .module)
        }
    }

    private func value(_ day: ReviewDay) -> Int { showsTime ? day.milliseconds : day.count }
    private func value(_ entry: ReviewDay.Entry) -> Int { showsTime ? entry.milliseconds : entry.count }

    private func chartValue(_ value: Int) -> Double {
        showsTime ? Double(value) / 60_000 : Double(value)
    }

    private func valueText(_ value: Int) -> Text {
        if showsTime {
            Text(Duration.milliseconds(value).formatted(.units(
                allowed: [.hours, .minutes, .seconds], width: .abbreviated,
                fractionalPart: .show(length: 1)
            ).locale(locale)))
        } else {
            Text(value, format: .number)
        }
    }
}

func relativeDay(_ offset: Int) -> Text {
    switch offset {
    case 0: Text("Today", bundle: .module)
    case -1: Text("Yesterday", bundle: .module)
    case 1: Text("Tomorrow", bundle: .module)
    case ..<0: Text("\(-offset, format: .number) days ago", bundle: .module)
    default: Text("In \(offset, format: .number) days", bundle: .module)
    }
}
