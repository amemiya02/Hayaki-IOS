import Charts
import SwiftUI

/// A bar chart of cards per day (or their running total) that can be
/// scrubbed for a day's exact count and scrolls when the range is long.
struct DailyCardCountChart: View {
    let days: [DailyCardCount]
    let range: ClosedRange<Int>
    let cumulative: Bool
    let title: Text
    /// The meaning color of the cards counted, such as Due or New.
    let color: Color
    /// The day the chart scrolls to first when the range is too long to fit.
    let initialDay: Int
    @Binding var position: Double?
    @Environment(\.statisticsReportPeriod) private var reportPeriod

    var body: some View {
        let runningTotals = days.reduce(into: [Int]()) { values, day in
            values.append((values.last ?? 0) + day.count)
        }
        return VStack(alignment: .trailing, spacing: 4) {
            // The axis title sits above the chart rather than in
            // chartYAxisLabel, which the scrolling plot area clipped.
            title
                .font(.caption)
                .foregroundStyle(.secondary)
            chart(runningTotals)
        }
    }

    private func chart(_ runningTotals: [Int]) -> some View {
        Chart {
            ForEach(days.indices, id: \.self) { index in
                let day = days[index]
                if cumulative {
                    LineMark(
                        x: .value(Text("Day", bundle: .module), Double(day.offset)),
                        y: .value(Text("Cards", bundle: .module), runningTotals[index])
                    )
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                    PointMark(
                        x: .value(Text("Day", bundle: .module), Double(day.offset)),
                        y: .value(Text("Cards", bundle: .module), runningTotals[index])
                    )
                    .foregroundStyle(color)
                    .accessibilityLabel(relativeDay(day.offset))
                    .accessibilityValue(Text(runningTotals[index], format: .number))
                } else {
                    RectangleMark(
                        xStart: .value(Text("Day", bundle: .module), Double(day.offset) - 0.4),
                        xEnd: .value(Text("Day", bundle: .module), Double(day.offset) + 0.4),
                        yStart: .value("Cards", 0),
                        yEnd: .value("Cards", day.count)
                    )
                    .foregroundStyle(color)
                    .accessibilityLabel(relativeDay(day.offset))
                    .accessibilityValue(Text(day.count, format: .number))
                }
            }
            if let position {
                let selected = Int(position.rounded())
                RuleMark(x: .value(Text("Day", bundle: .module), Double(selected)))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    .annotation(position: .top, spacing: 4, overflowResolution: calloutOverflow) {
                        callout(selected)
                    }
            }
        }
        .chartXScale(domain: (Double(range.lowerBound) - 0.5)...(Double(range.upperBound) + 0.5))
        .chartXSelection(value: $position)
        .dailyChartScrolling(range: range, initialDay: initialDay, enabled: reportPeriod == nil)
        .frame(height: 180)
    }

    private func callout(_ selected: Int) -> some View {
        let count = days.first { $0.offset == selected }?.count ?? 0
        let total = days.lazy.filter { $0.offset <= selected }.reduce(0) { $0 + $1.count }
        return ChartCallout(
            title: relativeDay(selected),
            value: Text(cumulative ? total : count, format: .number),
            details: cumulative ? [] : [(Text("Running Total", bundle: .module), Text(total, format: .number))]
        )
    }
}
