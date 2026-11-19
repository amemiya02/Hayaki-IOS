import Charts
import SwiftUI

struct HourlySection: View {
    let hours: [HourlyReviews]
    @State private var position: Double?

    var body: some View {
        StatisticsSectionView(
            title: Text("Hourly Breakdown", bundle: .module),
            emptyMessage: hours.contains { $0.count > 0 } ? nil :
                Text("There are no reviews in this period.", bundle: .module)
        ) {
            chart
            if let selected = position.map({ Int($0.rounded()) }), let hour = hours.first(where: { $0.hour == selected }) {
                LabeledContent {
                    value(for: hour)
                } label: {
                    hourLabel(hour.hour)
                }
            }
        }
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
                .foregroundStyle(.blue.opacity(0.64))
                .accessibilityLabel(hourLabel(hour.hour))
                .accessibilityValue(value(for: hour))
                if let rate = hour.successRate {
                    LineMark(
                        x: .value("Hour", Double(hour.hour)),
                        y: .value("Correct", rate * Double(maximum))
                    )
                    .foregroundStyle(.orange)
                    .symbol(.circle)
                    .accessibilityHidden(true)
                }
            }
            if let position {
                RuleMark(x: .value("Hour", position.rounded()))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
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
