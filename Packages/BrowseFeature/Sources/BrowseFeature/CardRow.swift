import AnkiProto

/// One card as the browser lists it, with the text the core shows for it.
public struct CardRow: Identifiable, Equatable, Sendable {
    public let id: Int64
    /// The display text from the core, keyed by browser column.
    public let cells: [String: String]
    public var question: String { cells["question"] ?? cells["noteFld"] ?? "" }
    public var deck: String { cells["deck"] ?? "" }
    public var due: String { cells["cardDue"] ?? "" }

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
