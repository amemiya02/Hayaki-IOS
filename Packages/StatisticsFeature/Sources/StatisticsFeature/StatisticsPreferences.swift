import AnkiProto

/// Collection-wide preferences shared with other clients.
public struct StatisticsPreferences: Equatable, Sendable {
    public enum Change: Sendable {
        case firstWeekday(StatisticsWeekday)
        case includeBacklog(Bool)
        case separateInactive(Bool)

        func apply(to target: inout Anki_Stats_GraphPreferences) {
            switch self {
            case .firstWeekday(let day):
                target.calendarFirstDayOfWeek = .init(rawValue: day.rawValue - 1) ?? .sunday
            case .includeBacklog(let include):
                target.futureDueShowBacklog = include
            case .separateInactive(let separate):
                target.cardCountsSeparateInactive = separate
            }
        }
    }

    public let firstWeekday: StatisticsWeekday
    public let includeBacklog: Bool
    public let separateInactive: Bool

    init(_ source: Anki_Stats_GraphPreferences) {
        self.firstWeekday = .init(rawValue: source.calendarFirstDayOfWeek.rawValue + 1) ?? .sunday
        self.includeBacklog = source.futureDueShowBacklog
        self.separateInactive = source.cardCountsSeparateInactive
    }
}
