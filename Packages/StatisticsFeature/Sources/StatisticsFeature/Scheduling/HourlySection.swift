import Charts
import HayakiAppearance
import SwiftUI

struct HourlySection: View {
    let graphs: StatisticsGraphs
    @Environment(\.statisticsReportPeriod) private var reportPeriod
    @Environment(\.hayakiTheme) private var theme
    private var displayedPeriod: StatisticsPeriod { reportPeriod ?? graphs.period }
    private var hours: [HourlyReviews] { graphs.displaying(displayedPeriod).hourlyReviews }
    @State private var position: Double?

    var body: some View {
        Section {
            if hours.contains(where: { $0.count > 0 }) {
                chart
            } else {
                Text("There are no reviews in this period.", bundle: .module)
                    .foregroundStyle(.secondary)
            }
        } header: {
            StatisticsCardHeader(title: Text("Hourly Breakdown", bundle: .module), reading: reading)
        }
        .onChange(of: graphs.period) { position = nil }
    }

    /// The hour with the most reviews.
    private var reading: Text? {
        guard let busiest = hours.max(by: { $0.count < $1.count }), busiest.count > 0 else { return nil }
        return Text(
            "You review most around \(hourLabel(busiest.hour))",
            bundle: .module,
            comment: "Hourly Breakdown card reading: the hour of the day with the most reviews, e.g. \"9 PM\"."
        )
    }

    private var chart: some View {
        let maximum = max(hours.map(\.count).max() ?? 0, 1)
        return Chart {
            ForEach(hours) { hour in
                RectangleMark(
                    xStart: .value("Hour", Double(hour.hour) - 0.4),
                    xEnd: .value("Hour", Double(hour.hour) + 0.4),
                    yStart: .value("Reviews", 0.0),
                    yEnd: .value("Reviews", Double(hour.count))
                )
                .foregroundStyle(theme.accent.opacity(0.7))
                .accessibilityLabel(hourLabel(hour.hour))
                .accessibilityValue(value(for: hour))
                if let rate = hour.successRate {
                    LineMark(
                        x: .value("Hour", Double(hour.hour)),
                        y: .value("Correct", rate * Double(maximum))
                    )
                    .foregroundStyle(SemanticColor.good.color)
                    .symbol(.circle)
                    .accessibilityHidden(true)
                }
            }
            if let position {
                RuleMark(x: .value("Hour", position.rounded()))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    .annotation(position: .top, spacing: 4, overflowResolution: calloutOverflow) {
                        if let hour = hours.first(where: { $0.hour == Int(position.rounded()) }) {
                            callout(hour)
                        }
                    }
            }
        }
        .chartXScale(domain: -0.5...23.5)
        .chartYScale(domain: 0.0...Double(maximum))
        .chartXSelection(value: $position)
        .chartXAxis {
            AxisMarks(values: [0, 4, 8, 12, 16, 20].map(Double.init)) { value in
                AxisGridLine()
                if let hour = value.as(Double.self) {
                    AxisValueLabel { Text(Int(hour), format: .number) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
            AxisMarks(position: .trailing, values: [0, 0.5, 1].map { $0 * Double(maximum) }) { value in
                if let count = value.as(Double.self) {
                    AxisValueLabel { Text(count / Double(maximum), format: .percent) }
                }
            }
        }
        .chartYAxisLabel(position: .leading) { Text("Reviews", bundle: .module) }
        .chartYAxisLabel(position: .trailing) { Text("Correct", bundle: .module) }
        .frame(height: 190)
    }

    private func callout(_ hour: HourlyReviews) -> some View {
        ChartCallout(
            title: hourLabel(hour.hour),
            value: Text("\(hour.count) reviews", bundle: .module),
            details: hour.successRate.map { rate in
                [(Text("Correct", bundle: .module), Text(rate, format: .percent.precision(.fractionLength(1))))]
            } ?? []
        )
    }

    private func hourLabel(_ hour: Int) -> Text {
        let calendar = Calendar.statisticsCalendar
        let day = calendar.startOfDay(for: .now)
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        return Text(date, format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
    }

    private func value(for hour: HourlyReviews) -> Text {
        if let rate = hour.successRate {
            Text("\(hour.correct, format: .number) of \(hour.count, format: .number) correct (\(rate, format: .percent.precision(.fractionLength(1))))", bundle: .module)
        } else {
            Text("No reviews", bundle: .module)
        }
    }
}
