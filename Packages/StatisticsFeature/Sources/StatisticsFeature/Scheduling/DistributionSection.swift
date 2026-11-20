import Charts
import HayakiAppearance
import SwiftUI

struct DistributionSection: View {
    let data: CardDistribution
    @Environment(\.statisticsReportPeriod) private var reportPeriod
    @Environment(\.hayakiTheme) private var theme
    @State private var range: DistributionRange?
    @State private var showCumulative = false
    @State private var position: Double?

    private enum DistributionRange: CaseIterable {
        case month, middle50, middle95, observed, all

        func title(for kind: CardDistribution.Kind) -> Text {
            switch self {
            case .month: Text("1 Month", bundle: .module)
            case .middle50: kind.usesDays ? Text("50th Percentile", bundle: .module) : Text("Middle 50%", bundle: .module)
            case .middle95: kind.usesDays ? Text("95th Percentile", bundle: .module) : Text("Middle 95%", bundle: .module)
            case .observed: Text("Observed Range", bundle: .module)
            case .all: Text("All", bundle: .module)
            }
        }
    }

    private struct Bin: Identifiable {
        let bounds: ClosedRange<Int>
        let count: Int
        var id: Int { bounds.lowerBound }
        var center: Double { Double(bounds.lowerBound + bounds.upperBound) / 2 }
    }

    private var availableRanges: [DistributionRange] {
        if data.kind.usesDays {
            [.month, .middle50, .middle95, .all]
        } else if data.kind.usesPercentageRange {
            [.all, .observed, .middle95, .middle50]
        } else {
            []
        }
    }

    private var selectedRange: Binding<DistributionRange> {
        Binding {
            if reportPeriod != nil { return .all }
            return range ?? (data.kind.usesDays ? .middle95 : .all)
        } set: { selected in
            range = selected
            position = nil
        }
    }

    private var bounds: ClosedRange<Int> {
        let first = data.buckets.first?.value ?? 0
        let last = data.buckets.last?.value ?? 0
        if data.kind.usesDays {
            let upper = switch selectedRange.wrappedValue {
            case .month: min(last, 30)
            case .middle50: Int(data.quantile(0.5).rounded(.up))
            case .middle95: Int(data.quantile(0.95).rounded(.up))
            case .observed, .all: last
            }
            return (data.kind == .intervals && upper > 0 ? 1 : 0)...upper
        }
        return switch selectedRange.wrappedValue {
        case .middle50: data.percentageQuantile(0.25)...data.percentageQuantile(0.75)
        case .middle95: data.percentageQuantile(0.025)...data.percentageQuantile(0.975)
        case .observed: first...last
        case .all, .month: data.kind == .ease ? first...last : 0...100
        }
    }

    private func bins(in bounds: ClosedRange<Int>) -> [Bin] {
        let width = max(1, (bounds.count + 69) / 70)
        let counts = Dictionary(grouping: data.buckets.filter { bounds.contains($0.value) }) {
            bounds.lowerBound + ($0.value - bounds.lowerBound) / width * width
        }
        return counts.keys.sorted().map { start in
            Bin(
                bounds: start...min(start + width - 1, bounds.upperBound),
                count: (counts[start] ?? []).reduce(0) { $0 + $1.count }
            )
        }
    }

    var body: some View {
        let shown = bins(in: bounds)
        Section {
            if reportPeriod == nil, !availableRanges.isEmpty {
                LabeledContent {
                    Picker(selection: selectedRange) {
                        ForEach(availableRanges, id: \.self) { range in
                            range.title(for: data.kind).tag(range)
                        }
                    } label: {
                        Text("Range", bundle: .module)
                    }
                    .labelsHidden()
                } label: {
                    Text("Range", bundle: .module)
                }
            }
            if shown.isEmpty {
                Text("There are no cards in this range.", bundle: .module)
                    .foregroundStyle(.secondary)
            } else {
                if reportPeriod == nil {
                    Toggle(isOn: $showCumulative) { Text("Running Total", bundle: .module) }
                }
                chart(shown)
                summary
            }
        } header: {
            StatisticsCardHeader(title: Text(data.kind.title), reading: data.buckets.isEmpty ? nil : reading)
        }
    }

    private var reading: Text {
        if data.kind.usesDays {
            Text(
                "Half of these cards are at \(Int(data.typicalValue.rounded()), format: .number) days or less",
                bundle: .module,
                comment: "Review Intervals and Card Stability card reading: the median in days."
            )
        } else if data.kind == .retrievability {
            Text(
                "Average retrievability is \(data.typicalValue / 100, format: .percent.precision(.fractionLength(0)))",
                bundle: .module,
                comment: "Card Retrievability card reading: the average chance of recalling a card."
            )
        } else {
            Text(
                "The average is \(data.typicalValue / 100, format: .percent.precision(.fractionLength(0)))",
                bundle: .module,
                comment: "Card Ease and Card Difficulty card reading: the average value."
            )
        }
    }

    private func chart(_ shown: [Bin]) -> some View {
        let total = shown.reduce(0) { $0 + $1.count }
        let runningTotals = shown.reduce(into: [Int]()) { values, bin in
            values.append((values.last ?? 0) + bin.count)
        }
        return Chart {
            ForEach(shown.indices, id: \.self) { index in
                let bin = shown[index]
                if showCumulative {
                    cumulativeMark(bin, fraction: Double(runningTotals[index]) / Double(total))
                } else {
                    countMark(bin)
                }
            }
            if let position {
                RuleMark(x: .value("Range", position))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    .annotation(position: .top, spacing: 4, overflowResolution: calloutOverflow) {
                        callout(shown, runningTotals: runningTotals, total: total, value: Int(position.rounded()))
                    }
            }
        }
        .chartXScale(domain: (Double(bounds.lowerBound) - 0.5)...(Double(bounds.upperBound) + 0.5))
        .chartXSelection(value: $position)
        .chartXAxisLabel {
            if data.kind.usesDays {
                Text("Days", bundle: .module)
            } else {
                Text("Percent", bundle: .module)
            }
        }
        .chartYAxisLabel {
            if showCumulative { Text("Share of Cards", bundle: .module) }
            else { Text("Cards", bundle: .module) }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                if showCumulative, let fraction = value.as(Double.self) {
                    AxisValueLabel { Text(fraction, format: .percent) }
                } else {
                    AxisValueLabel()
                }
            }
        }
        .frame(height: 180)
    }

    private func countMark(_ bin: Bin) -> some ChartContent {
        RectangleMark(
            xStart: .value("Range", Double(bin.bounds.lowerBound) - 0.4),
            xEnd: .value("Range", Double(bin.bounds.upperBound) + 0.4),
            yStart: .value("Cards", 0.0),
            yEnd: .value("Cards", Double(bin.count))
        )
        .foregroundStyle(theme.accent)
        .accessibilityLabel(bucketLabel(bin.bounds))
        .accessibilityValue(Text(bin.count, format: .number))
    }

    @ChartContentBuilder
    private func cumulativeMark(_ bin: Bin, fraction: Double) -> some ChartContent {
        LineMark(x: .value("Range", bin.center), y: .value("Share", fraction))
            .foregroundStyle(theme.accent)
            .accessibilityHidden(true)
        PointMark(x: .value("Range", bin.center), y: .value("Share", fraction))
            .foregroundStyle(theme.accent)
            .accessibilityLabel(bucketLabel(bin.bounds))
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(1))))
    }

    @ViewBuilder
    private var summary: some View {
        LabeledContent {
            if data.kind.usesDays {
                Text("\(Int(data.typicalValue.rounded()), format: .number) days", bundle: .module)
            } else {
                Text(data.typicalValue / 100, format: .percent.precision(.fractionLength(1)))
            }
        } label: {
            if data.kind == .retrievability {
                Text("Average Retrievability", bundle: .module)
            } else {
                Text("Median", bundle: .module)
            }
        }
        if let cards = data.estimatedRememberedCards, let notes = data.estimatedRememberedNotes {
            LabeledContent {
                Text(Int(cards.rounded()), format: .number)
            } label: {
                Text("Estimated Cards Remembered", bundle: .module)
            }
            LabeledContent {
                Text(Int(notes.rounded()), format: .number)
            } label: {
                Text("Estimated Notes Remembered", bundle: .module)
            }
        }
    }

    private func callout(_ shown: [Bin], runningTotals: [Int], total: Int, value: Int) -> some View {
        let index = shown.firstIndex { $0.bounds.contains(value) }
        let bin = index.map { shown[$0] }
        let share = Double(index.map { runningTotals[$0] } ?? shown.lazy.filter { $0.bounds.upperBound < value }
            .reduce(0) { $0 + $1.count }) / Double(max(total, 1))
        return ChartCallout(
            title: bucketLabel(bin?.bounds ?? (value...value)),
            value: showCumulative
                ? Text(share, format: .percent.precision(.fractionLength(1)))
                : Text("\(bin?.count ?? 0) cards", bundle: .module),
            details: showCumulative ? [] : [
                (Text("Running Total", bundle: .module), Text(share, format: .percent.precision(.fractionLength(1)))),
            ]
        )
    }

    private func bucketLabel(_ range: ClosedRange<Int>) -> Text {
        if range.lowerBound == range.upperBound {
            return data.kind.usesDays
                ? Text("\(range.lowerBound, format: .number) days", bundle: .module)
                : Text(Double(range.lowerBound) / 100, format: .percent)
        }
        return data.kind.usesDays
            ? Text("\(range.lowerBound, format: .number)–\(range.upperBound, format: .number) days", bundle: .module)
            : Text("\(range.lowerBound, format: .number)–\(range.upperBound, format: .number)%", bundle: .module)
    }
}
