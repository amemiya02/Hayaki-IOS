import AnkiProto

/// The states a card can be in, as the card counts chart groups them.
public enum CardState: CaseIterable, Hashable, Sendable {
    /// Never studied.
    case new
    /// Being learnt or relearnt after a lapse.
    case learning
    /// In review with an interval under 21 days.
    case young
    /// In review with an interval of 21 days or more.
    case mature
    case suspended
    case buried

    public var title: String {
        switch self {
        case .new: String(localized: "New", bundle: .module, comment: "Card state: never studied.")
        case .learning: String(localized: "Learning", bundle: .module, comment: "Card state: being learnt or relearnt.")
        case .young: String(localized: "Young", bundle: .module, comment: "Card state: in review with an interval under 21 days.")
        case .mature: String(localized: "Mature", bundle: .module, comment: "Card state: in review with an interval of 21 days or more.")
        case .suspended: String(localized: "Suspended", bundle: .module, comment: "Card state: suspended by the learner.")
        case .buried: String(localized: "Buried", bundle: .module, comment: "Card state: buried until tomorrow.")
        }
    }
}

/// How the cards of the chosen deck or the whole collection divide between
/// states. Suspended and buried cards are counted only as such, so every card
/// is counted once.
public struct CardCounts: Equatable, Sendable {
    public struct Entry: Identifiable, Equatable, Sendable {
        public let state: CardState
        public let count: Int
        public var id: CardState { state }
    }

    /// One entry per state, in `CardState` order, including empty ones.
    public let entries: [Entry]

    public var total: Int { entries.reduce(0) { $0 + $1.count } }
    public var isEmpty: Bool { total == 0 }

    public func count(_ state: CardState) -> Int {
        entries.first { $0.state == state }?.count ?? 0
    }

    /// The share of all cards in `state`, from 0 to 1.
    public func fraction(_ state: CardState) -> Double {
        isEmpty ? 0 : Double(count(state)) / Double(total)
    }

    init(_ counts: Anki_Stats_GraphsResponse.CardCounts) {
        // The core's counts that keep inactive (suspended, buried) cards apart.
        let counts = counts.excludingInactive
        entries = CardState.allCases.map { state in
            let count: UInt32 = switch state {
            case .new: counts.newCards
            case .learning: counts.learn + counts.relearn
            case .young: counts.young
            case .mature: counts.mature
            case .suspended: counts.suspended
            case .buried: counts.buried
            }
            return Entry(state: state, count: Int(count))
        }
    }
}

extension StatisticsGraphs {
    /// The values behind the card counts chart.
    public var cardCounts: CardCounts {
        CardCounts(response.cardCounts)
    }
}
