import Charts
import SwiftUI

struct ReviewHistorySection: View {
    let days: [ReviewDay]
    let earliestDay: Int

    @State private var showTime = false
    @State private var showCumulative = false
    @State private var position: Double?
    private var selection: Int? { position.map { Int($0.rounded()) } }

    private var firstDay: Int { earliestDay == .min ? days.first?.offset ?? 0 : earliestDay }

    var body: some View {
        Section {
            Toggle(isOn: $showTime) { Text("Review Time", bundle: .module) }
            if days.isEmpty {
                Text("There are no reviews in this period.", bundle: .module)
                    .foregroundStyle(.secondary)
            } else {
                Toggle(isOn: $showCumulative) { Text("Running Total", bundle: .module) }
                chart
                summary
            }
        } header: {
            Text("Reviews", bundle: .module)
        }
    }

    private var chart: some View {
        Chart {
            if showCumulative {
                cumulativeMarks
            } else {
                dailyMarks
            }
            if let selection {
                RuleMark(x: .value("Day", Double(selection)))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .chartXScale(domain: (Double(firstDay) - 0.5)...0.5)
        .chartForegroundStyleScale(
            domain: StatisticsReviewKind.allCases.map(\.title),
            range: StatisticsReviewKind.allCases.map(\.color)
        )
        .chartLegend(showCumulative ? .hidden : .visible)
        .chartXSelection(value: $position)
        .chartYAxisLabel { metric }
        .frame(height: 210)
        .onChange(of: earliestDay) { position = nil }
    }

    @ChartContentBuilder
    private var cumulativeMarks: some ChartContent {
        let totals = days.reduce(into: [Int]()) { values, day in
            values.append((values.last ?? 0) + value(day))
        }
        ForEach(days.indices, id: \.self) { index in
            let day = days[index]
            LineMark(x: .value("Day", Double(day.offset)), y: .value(metric, chartValue(totals[index])))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            PointMark(x: .value("Day", Double(day.offset)), y: .value(metric, chartValue(totals[index])))
                .foregroundStyle(.blue)
                .accessibilityLabel(relativeDay(day.offset))
                .accessibilityValue(valueText(totals[index]))
        }
    }

    @ChartContentBuilder
    private var dailyMarks: some ChartContent {
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
    private var summary: some View {
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
        if showTime, count > 0 {
            LabeledContent {
                valueText(total / count)
            } label: {
                Text("Average Answer Time", bundle: .module)
            }
        }
        if let selection {
            let day = days.first { $0.offset == selection }
            LabeledContent {
                valueText(day.map { value($0) } ?? 0)
            } label: {
                relativeDay(selection)
            }
            if let day, !showCumulative {
                ForEach(day.entries) { entry in
                    LabeledContent {
                        valueText(value(entry))
                    } label: {
                        Text(entry.kind.title)
                    }
                }
            }
            LabeledContent {
                valueText(days.lazy.filter { $0.offset <= selection }.reduce(0) { $0 + value($1) })
            } label: {
                Text("Running Total", bundle: .module)
            }
        }
    }

    private var metric: Text {
        if showTime {
            Text("Minutes", bundle: .module)
        } else {
            Text("Reviews", bundle: .module)
        }
    }

    private func value(_ day: ReviewDay) -> Int { showTime ? day.milliseconds : day.count }
    private func value(_ entry: ReviewDay.Entry) -> Int { showTime ? entry.milliseconds : entry.count }

    private func chartValue(_ value: Int) -> Double {
        showTime ? Double(value) / 60_000 : Double(value)
    }

    private func valueText(_ value: Int) -> Text {
        if showTime {
            Text(Duration.milliseconds(value).formatted(.units(
                allowed: [.hours, .minutes, .seconds], width: .abbreviated,
                fractionalPart: .show(length: 1)
            )))
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
