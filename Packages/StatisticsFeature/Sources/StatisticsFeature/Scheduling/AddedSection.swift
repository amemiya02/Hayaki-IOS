import SwiftUI

struct AddedSection: View {
    let graphs: StatisticsGraphs
    @Environment(\.statisticsReportPeriod) private var reportPeriod
    private var displayedPeriod: StatisticsPeriod { reportPeriod ?? graphs.period }
    @State private var showCumulative = false
    @State private var position: Double?

    var body: some View {
        let days = graphs.displaying(displayedPeriod).addedDays
        let earliest = displayedPeriod == .allTime
            ? min(days.first?.offset ?? 0, 0)
            : -displayedPeriod.latestForecastDay
        let total = days.reduce(0) { $0 + $1.count }

        Section {
            if days.isEmpty {
                Text("No cards were added in this period.", bundle: .module)
                    .foregroundStyle(.secondary)
            } else {
                results(days: days, earliest: earliest, total: total)
            }
        } header: {
            StatisticsCardHeader(
                title: Text("Added", bundle: .module),
                reading: days.isEmpty ? nil : Text(
                    "\(total, format: .number) cards added, about \(Int((Double(total) / Double(max(1, -earliest))).rounded()), format: .number) per day",
                    bundle: .module,
                    comment: "Added card reading: cards added in the period, and the average per day."
                )
            )
        }
        .onChange(of: graphs.period) { position = nil }
    }

    @ViewBuilder
    private func results(days: [DailyCardCount], earliest: Int, total: Int) -> some View {
        if reportPeriod == nil {
            Toggle(isOn: $showCumulative) { Text("Running Total", bundle: .module) }
        }
        DailyCardCountChart(
            days: days, range: earliest...1, cumulative: showCumulative,
            title: Text("Cards Added", bundle: .module), position: $position
        )
        LabeledContent {
            Text(total, format: .number)
        } label: {
            Text("Total", bundle: .module)
        }
        LabeledContent {
            Text((Double(total) / Double(max(1, -earliest))).rounded(), format: .number)
        } label: {
            Text("Average Added per Day", bundle: .module)
        }
        if let position {
            let offset = Int(position.rounded())
            LabeledContent {
                Text(days.first { $0.offset == offset }?.count ?? 0, format: .number)
            } label: {
                relativeDay(offset)
            }
            LabeledContent {
                Text(days.lazy.filter { $0.offset <= offset }.reduce(0) { $0 + $1.count }, format: .number)
            } label: {
                Text("Running Total", bundle: .module)
            }
        }
    }
}
