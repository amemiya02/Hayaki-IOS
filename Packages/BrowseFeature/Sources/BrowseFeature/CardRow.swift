import AnkiProto

/// One card as the browser lists it, with the text the core shows for it.
public struct CardRow: Identifiable, Equatable, Sendable {
    public let id: Int64
    /// The card's question, rendered and reduced to plain text by the core.
    public let question: String
    /// The full name of the card's deck.
    public let deck: String
    /// When the card is due, as the core words it: a date, a position among
    /// new cards, or a date in parentheses for a suspended or buried card.
    public let due: String
    /// How the core marks the card: flagged, marked, suspended or buried.
    public let mark: Mark

    public enum Mark: Equatable, Sendable {
        case none
        case flag(Flag)
        case marked
        case suspended
        case buried
    }

    /// The seven card flags, numbered as Anki numbers them.
    public enum Flag: Int, CaseIterable, Sendable {
        case red = 1, orange, green, blue, pink, turquoise, purple
    }

    init(id: Int64, _ row: Anki_Search_BrowserRow) {
        self.id = id
        // The cells come in the order of CardBrowserModel.columns.
        func cell(_ index: Int) -> String {
            index < row.cells.count ? row.cells[index].text : ""
        }
        question = cell(0)
        deck = cell(1)
        due = cell(2)
        mark = switch row.color {
        case .flagRed: .flag(.red)
        case .flagOrange: .flag(.orange)
        case .flagGreen: .flag(.green)
        case .flagBlue: .flag(.blue)
        case .flagPink: .flag(.pink)
        case .flagTurquoise: .flag(.turquoise)
        case .flagPurple: .flag(.purple)
        case .marked: .marked
        case .suspended: .suspended
        case .buried: .buried
        case .default, .UNRECOGNIZED: .none
        }
    }
}
