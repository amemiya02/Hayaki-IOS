import Charts
import SwiftUI

struct CardRetentionChart: View {
    let detail: CardDetail
    @State private var range = Range.all
    @State private var selectedDate: Date?

    private enum Range: String, CaseIterable {
        case week, month, year, all

        var days: Int? {
            switch self {
            case .week: 7
            case .month: 30
            case .year: 365
            case .all: nil
            }
        }

        var title: Text {
            switch self {
            case .week: Text("First Week", bundle: .module)
            case .month: Text("First Month", bundle: .module)
            case .year: Text("First Year", bundle: .module)
            case .all: Text("All Time", bundle: .module)
            }
        }
    }

    var body: some View {
        let points = detail.retentionPoints(dayLimit: range.days)
        if !points.isEmpty {
            Section {
                if detail.retentionHistoryDays > 7 {
                    Picker(selection: $range) {
                        ForEach(Range.allCases.filter { ($0.days ?? 0) <= detail.retentionHistoryDays }, id: \.self) { range in
                            range.title.tag(range)
                        }
                    } label: {
                        Text("Time Range", bundle: .module)
                    }
                }
                plot(points)
                if let selectedDate,
                   let nearest = points.min(by: {
                       abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
                   }) {
                    LabeledContent {
                        Text(nearest.probability, format: .percent.precision(.fractionLength(0)))
                    } label: {
                        Text(nearest.date, format: .dateTime.year().month().day().hour().minute())
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("Forgetting Curve", bundle: .module)
            }
            .onChange(of: range) { _, _ in selectedDate = nil }
        }
    }

    private func plot(_ points: [CardDetail.RetentionPoint]) -> some View {
        Chart {
            RuleMark(y: .value(String(localized: "Desired Retention", bundle: .module), detail.desiredRetention ?? 0.9))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.secondary)
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value(String(localized: "Review Date", bundle: .module), point.date),
                    y: .value(String(localized: "Retrievability", bundle: .module), point.probability),
                    series: .value(String(localized: "Review", bundle: .module), point.reviewIndex)
                )
            }
            if let selectedDate {
                RuleMark(x: .value(String(localized: "Selected Date", bundle: .module), selectedDate))
                    .foregroundStyle(.secondary)
            }
        }
        .chartYScale(domain: 0.0...1.0)
        .chartYAxis {
            AxisMarks(values: [0, 0.25, 0.5, 0.75, 1]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Double.self) {
                        Text(percent, format: .percent)
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .frame(minHeight: 180)
    }
}
