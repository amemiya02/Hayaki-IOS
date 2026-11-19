import Charts
import SwiftUI

struct ForecastSection: View {
    let graphs: StatisticsGraphs
    @Binding var includeBacklog: Bool
    @State private var showCumulative = false
    @State private var position: Double?

    var body: some View {
        let forecast = graphs.forecast(includeBacklog: includeBacklog)
        Section {
            if forecast.hasBacklog {
                Toggle(isOn: $includeBacklog) { Text("Show Backlog", bundle: .module) }
            }
            if forecast.days.isEmpty {
                Text("There are no cards due in this period.", bundle: .module)
                    .foregroundStyle(.secondary)
            } else {
                Toggle(isOn: $showCumulative) { Text("Running Total", bundle: .module) }
                chart(forecast)
                summary(forecast)
            }
        } header: {
            Text("Future Due", bundle: .module)
        }
        .onChange(of: graphs.period) { position = nil }
        .onChange(of: includeBacklog) { position = nil }
    }

    private func chart(_ forecast: DueForecast) -> some View {
        let earliest = min(forecast.days.first?.offset ?? 0, 0)
        let maximum = graphs.period.latestForecastDay
        let latest = maximum == .max ? max(forecast.days.last?.offset ?? 0, 0) : maximum
        let runningTotals = forecast.days.reduce(into: [Int]()) { values, day in
            values.append((values.last ?? 0) + day.count)
        }
        return Chart {
            ForEach(forecast.days.indices, id: \.self) { index in
                let day = forecast.days[index]
                if showCumulative {
                    LineMark(
                        x: .value(Text("Day", bundle: .module), Double(day.offset)),
                        y: .value(Text("Cards", bundle: .module), runningTotals[index])
                    )
                    .foregroundStyle(.blue)
                    PointMark(
                        x: .value(Text("Day", bundle: .module), Double(day.offset)),
                        y: .value(Text("Cards", bundle: .module), runningTotals[index])
                    )
                    .foregroundStyle(.blue)
                    .accessibilityLabel(relativeDay(day.offset))
                    .accessibilityValue(Text(runningTotals[index], format: .number))
                } else {
                    RectangleMark(
                        xStart: .value(Text("Day", bundle: .module), Double(day.offset) - 0.4),
                        xEnd: .value(Text("Day", bundle: .module), Double(day.offset) + 0.4),
                        yStart: .value("Cards", 0),
                        yEnd: .value("Cards", day.count)
                    )
                    .foregroundStyle(.green)
                    .accessibilityLabel(relativeDay(day.offset))
                    .accessibilityValue(Text(day.count, format: .number))
                }
            }
            if let position {
                RuleMark(x: .value(Text("Day", bundle: .module), position.rounded()))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .chartXScale(domain: (Double(earliest) - 0.5)...(Double(latest) + 0.5))
        .chartXSelection(value: $position)
        .chartYAxisLabel { Text("Cards Due", bundle: .module) }
        .frame(height: 180)
    }

    @ViewBuilder
    private func summary(_ forecast: DueForecast) -> some View {
        let earliest = includeBacklog ? forecast.days.first?.offset ?? 0 : 0
        let maximum = graphs.period.latestForecastDay
        let latest = maximum == .max ? forecast.days.last?.offset ?? 0 : maximum
        let average = Double(forecast.total) / Double(max(1, latest - earliest))
        LabeledContent {
            Text(forecast.total, format: .number)
        } label: {
            Text("Total", bundle: .module)
        }
        LabeledContent {
            Text(average.rounded(), format: .number)
        } label: {
            Text("Average Due per Day", bundle: .module)
        }
        LabeledContent {
            Text(forecast.tomorrow, format: .number)
        } label: {
            Text("Due Tomorrow", bundle: .module)
        }
        LabeledContent {
            Text(forecast.dailyLoad, format: .number)
        } label: {
            Text("Daily Load", bundle: .module)
        }
        if let position {
            let selected = Int(position.rounded())
            LabeledContent {
                Text(forecast.days.first { $0.offset == selected }?.count ?? 0, format: .number)
            } label: {
                relativeDay(selected)
            }
            LabeledContent {
                Text(forecast.days.lazy.filter { $0.offset <= selected }.reduce(0) { $0 + $1.count }, format: .number)
            } label: {
                Text("Running Total", bundle: .module)
            }
        }
    }
}
