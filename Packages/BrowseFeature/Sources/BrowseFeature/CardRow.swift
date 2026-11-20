import AnkiProto

/// One card as the browser lists it, with the text the core shows for it.
public struct CardRow: Identifiable, Equatable, Sendable {
    public let id: Int64
    /// The display text from the core, keyed by browser column.
    public let cells: [String: String]
    public var question: String { cells["question"] ?? cells["noteFld"] ?? "" }
    /// The note's sort field, the row's primary text.
    public var sortField: String { cells[Self.sortFieldColumn] ?? question }
    public var deck: String { cells[Self.deckColumn] ?? "" }
    public var due: String { cells[Self.dueColumn] ?? "" }

    /// The flag of a flagged card, shown as a colored bar on its row.
    public var flag: Flag? {
        if case .flag(let flag) = mark { flag } else { nil }
    }

    /// Whether the row is dimmed: its card is suspended.
    public var isDimmed: Bool { mark == .suspended }

    static let sortFieldColumn = "noteFld"
    static let deckColumn = "deck"
    static let dueColumn = "cardDue"
    /// The columns every row shows as its primary and secondary text, fetched
    /// whatever columns the learner chose.
    static let summaryColumns = [sortFieldColumn, deckColumn, dueColumn]

    /// The shown columns the row lists as details: those its primary and
    /// secondary text do not already show.
    public func detailColumns(_ columns: [BrowserColumn]) -> [BrowserColumn] {
        columns.filter { !Self.summaryColumns.contains($0.id) }
    }

    /// The engine brackets audio filenames with speaker symbols.
    public func displayText(for column: String, showsMediaFilenames: Bool) -> String {
        let text = cells[column] ?? ""
        return showsMediaFilenames ? text : text.replacing(/🔉[^🔉]*🔉/, with: "")
    }
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

    init(id: Int64, _ row: Anki_Search_BrowserRow, columnIDs: [String]) {
        self.id = id
        cells = Dictionary(uniqueKeysWithValues: zip(columnIDs, row.cells.map(\.text)))
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
