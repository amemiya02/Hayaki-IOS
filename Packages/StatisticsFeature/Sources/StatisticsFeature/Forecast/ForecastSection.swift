import SwiftUI

struct ForecastSection: View {
    let graphs: StatisticsGraphs
    @Binding var includeBacklog: Bool
    @State private var period: StatisticsPeriod = .month
    @State private var showCumulative = false
    @State private var position: Double?

    var body: some View {
        let forecast = graphs.displaying(period).forecast(includeBacklog: includeBacklog)
        Section {
            StatisticsPeriodPicker(selection: $period, label: Text("Forecast Period", bundle: .module))
            if forecast.hasBacklog {
                Toggle(isOn: $includeBacklog) { Text("Show Backlog", bundle: .module) }
            }
            if forecast.days.isEmpty {
                Text("There are no cards due in this period.", bundle: .module)
                    .foregroundStyle(.secondary)
            } else {
                Toggle(isOn: $showCumulative) { Text("Running Total", bundle: .module) }
                DailyCardCountChart(
                    days: forecast.days, range: chartRange(for: forecast),
                    cumulative: showCumulative, title: Text("Cards Due", bundle: .module), position: $position
                )
                summary(forecast)
            }
        } header: {
            Text("Future Due", bundle: .module)
        }
        .onChange(of: period) { position = nil }
        .onChange(of: includeBacklog) { position = nil }
    }

    private func chartRange(for forecast: DueForecast) -> ClosedRange<Int> {
        let earliest = min(forecast.days.first?.offset ?? 0, 0)
        let latest = period.latestForecastDay == .max
            ? max(forecast.days.last?.offset ?? 0, 0)
            : period.latestForecastDay
        return earliest...latest
    }

    @ViewBuilder
    private func summary(_ forecast: DueForecast) -> some View {
        let earliest = includeBacklog ? forecast.days.first?.offset ?? 0 : 0
        let maximum = period.latestForecastDay
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
