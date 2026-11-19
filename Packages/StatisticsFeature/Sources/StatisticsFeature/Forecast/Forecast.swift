import AnkiProto

public struct DueForecast: Equatable, Sendable {
    public struct Day: Identifiable, Equatable, Sendable {
        public let offset: Int
        public let count: Int
        public var id: Int { offset }
    }

    public let days: [Day]
    public let hasBacklog: Bool
    public let dailyLoad: Int
    public var total: Int { days.reduce(0) { $0 + $1.count } }
    public var tomorrow: Int { days.first { $0.offset == 1 }?.count ?? 0 }
}

extension StatisticsGraphs {
    /// Cards due in the selected period. A negative offset is an overdue card.
    public func forecast(includeBacklog: Bool = false) -> DueForecast {
        let future = response.futureDue
        let days = future.futureDue.compactMap { offset, count -> DueForecast.Day? in
            guard Int(offset) <= period.latestForecastDay, includeBacklog || offset >= 0 else { return nil }
            return DueForecast.Day(offset: Int(offset), count: Int(count))
        }
        return DueForecast(
            days: days.sorted { $0.offset < $1.offset },
            hasBacklog: future.haveBacklog,
            dailyLoad: Int(future.dailyLoad)
        )
    }
}
