import Charts
import SwiftUI

/// How a daily chart scrolls: a chart longer than `visibleDays` shows that
/// many days at a time and scrolls sideways, keeping its value axis in place.
public enum DailyChartScrolling {
    public static let visibleDays = 92

    /// The number of days shown at once, or `nil` when the whole range fits.
    public static func visibleLength(for range: ClosedRange<Int>) -> Int? {
        range.count > visibleDays ? visibleDays : nil
    }

    /// The first day of a scrolled window whose last day is `lastDay`, for
    /// charts that open on their most recent days.
    public static func firstVisibleDay(endingAt lastDay: Int) -> Int {
        lastDay - visibleDays + 1
    }
}

/// The value callout shown above a chart while a finger scrubs across it.
struct ChartCallout: View {
    let title: Text
    let value: Text
    /// Smaller label and value lines under the main value, such as a running total.
    var details: [(label: Text, value: Text)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .font(.caption)
                .foregroundStyle(.secondary)
            value
                .font(.headline)
                .monospacedDigit()
            ForEach(details.indices, id: \.self) { index in
                HStack(spacing: 4) {
                    details[index].label
                    details[index].value.monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Scrolls a daily chart sideways when its range is longer than
    /// `DailyChartScrolling.visibleDays`, starting at `initialDay`. The PDF
    /// report always shows the whole range.
    @ViewBuilder
    func dailyChartScrolling(range: ClosedRange<Int>, initialDay: Int, enabled: Bool = true) -> some View {
        if enabled, let length = DailyChartScrolling.visibleLength(for: range) {
            chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: Double(length))
                .chartScrollPosition(initialX: Double(initialDay) - 0.5)
        } else {
            self
        }
    }
}

/// The overflow rule for callouts: stay inside the chart sideways, and rise
/// above the plot when there is no room over the selected value.
var calloutOverflow: AnnotationOverflowResolution {
    AnnotationOverflowResolution(x: .fit(to: .chart), y: .disabled)
}
