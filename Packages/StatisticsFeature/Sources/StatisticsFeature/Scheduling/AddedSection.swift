import SwiftUI

struct AddedSection: View {
    let graphs: StatisticsGraphs
    @State private var period: StatisticsPeriod = .month
    @State private var showCumulative = false
    @State private var position: Double?

    var body: some View {
        let days = graphs.displaying(period).addedDays
        let earliest = period == .allTime
            ? min(days.first?.offset ?? 0, 0)
            : -period.latestForecastDay
        let total = days.reduce(0) { $0 + $1.count }

        Section {
            StatisticsPeriodPicker(selection: $period, label: Text("Added Period", bundle: .module))
            if days.isEmpty {
                Text("No cards were added in this period.", bundle: .module)
                    .foregroundStyle(.secondary)
            } else {
                results(days: days, earliest: earliest, total: total)
            }
        } header: {
            Text("Added", bundle: .module)
        }
        .onChange(of: period) { position = nil }
    }

    @ViewBuilder
    private func results(days: [DailyCardCount], earliest: Int, total: Int) -> some View {
        Toggle(isOn: $showCumulative) { Text("Running Total", bundle: .module) }
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
