import AnkiProto
import Foundation

/// The core's graphs data for one scope and period, from which every chart
/// takes its values.
///
/// Each chart adds, in its own file, an extension with a computed property
/// that turns the response into the plain values the chart draws (for
/// example `today` or `cardCounts`), so charts can be added without touching
/// each other.
public struct StatisticsGraphs: Sendable {
    /// The core's response to `Graphs` for this scope and period.
    public let response: Anki_Stats_GraphsResponse
    /// The period shown by the chart.
    public let period: StatisticsPeriod

    /// The calendar day that contains the start of the current study day.
    public let studyDate: Date

    public init(response: Anki_Stats_GraphsResponse, period: StatisticsPeriod, studyDate: Date = .now) {
        self.response = response
        self.period = period
        self.studyDate = studyDate
    }

    /// Changes a chart's visible range without reading from the core again.
    func displaying(_ period: StatisticsPeriod) -> Self {
        Self(response: response, period: period, studyDate: studyDate)
    }
}
