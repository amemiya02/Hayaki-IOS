import Charts
import SwiftUI

struct DailyCardCountChart: View {
    let days: [DailyCardCount]
    let range: ClosedRange<Int>
    let cumulative: Bool
    let title: Text
    @Binding var position: Double?

    var body: some View {
        let runningTotals = days.reduce(into: [Int]()) { values, day in
            values.append((values.last ?? 0) + day.count)
        }
        return Chart {
            ForEach(days.indices, id: \.self) { index in
                let day = days[index]
                if cumulative {
                    LineMark(
                        x: .value(Text("Day", bundle: .module), Double(day.offset)),
                        y: .value(Text("Cards", bundle: .module), runningTotals[index])
                    )
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
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
                    .foregroundStyle(.teal)
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
        .chartXScale(domain: (Double(range.lowerBound) - 0.5)...(Double(range.upperBound) + 0.5))
        .chartXSelection(value: $position)
        .chartYAxisLabel { title }
        .frame(height: 180)
    }
}
