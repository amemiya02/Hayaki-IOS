import HayakiAppearance
import SwiftUI

struct ForecastSection: View {
    let graphs: StatisticsGraphs
    @Environment(\.statisticsReportPeriod) private var reportPeriod
    private var displayedPeriod: StatisticsPeriod { reportPeriod ?? graphs.period }
    @Binding var includeBacklog: Bool
    @State private var showCumulative = false
    @State private var position: Double?

    var body: some View {
        let forecast = graphs.displaying(displayedPeriod).forecast(includeBacklog: includeBacklog)
        Section {
            if forecast.hasBacklog {
                if reportPeriod == nil {
                    Toggle(isOn: $includeBacklog) { Text("Show Backlog", bundle: .module) }
                }
            }
            if forecast.days.isEmpty {
                Text("There are no cards due in this period.", bundle: .module)
                    .foregroundStyle(.secondary)
            } else {
                if reportPeriod == nil {
                    Toggle(isOn: $showCumulative) { Text("Running Total", bundle: .module) }
                }
                DailyCardCountChart(
                    days: forecast.days, range: chartRange(for: forecast),
                    cumulative: showCumulative, title: Text("Cards Due", bundle: .module),
                    color: SemanticColor.due.color, initialDay: chartRange(for: forecast).lowerBound,
                    position: $position
                )
                summary(forecast)
            }
        } header: {
            StatisticsCardHeader(title: Text("Future Due", bundle: .module), reading: reading(forecast))
        }
        .onChange(of: graphs.period) { position = nil }
        .onChange(of: includeBacklog) { position = nil }
    }

    private func chartRange(for forecast: DueForecast) -> ClosedRange<Int> {
        let earliest = min(forecast.days.first?.offset ?? 0, 0)
        let latest = displayedPeriod.latestForecastDay == .max
            ? max(forecast.days.last?.offset ?? 0, 0)
            : displayedPeriod.latestForecastDay
        return earliest...latest
    }

    /// The first and last day the forecast covers.
    private func span(_ forecast: DueForecast) -> (earliest: Int, latest: Int) {
        let earliest = includeBacklog ? forecast.days.first?.offset ?? 0 : 0
        let maximum = displayedPeriod.latestForecastDay
        let latest = maximum == .max ? forecast.days.last?.offset ?? 0 : maximum
        return (earliest, latest)
    }

    private func average(_ forecast: DueForecast) -> Double {
        let (earliest, latest) = span(forecast)
        return Double(forecast.total) / Double(max(1, latest - earliest))
    }

    private func reading(_ forecast: DueForecast) -> Text? {
        guard !forecast.days.isEmpty else { return nil }
        let days = max(1, span(forecast).latest)
        return Text(
            "About \(Int(average(forecast).rounded()), format: .number) cards due per day over the next \(days, format: .number) days",
            bundle: .module,
            comment: "Future Due card reading: the average number of cards due each day, and the number of days ahead."
        )
    }

    @ViewBuilder
    private func summary(_ forecast: DueForecast) -> some View {
        let average = average(forecast)
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
    }
}
