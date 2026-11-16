import AnkiProto

/// The order of the cards in the browser: by one of the core's browser
/// columns, ascending or reversed.
public struct CardSort: Hashable, Sendable {
    /// The core's key for the column, such as `"noteCrt"` for when the note
    /// was created.
    public var column: String
    /// Whether the order is reversed: descending instead of ascending.
    public var reverse: Bool

    public init(column: String, reverse: Bool = false) {
        self.column = column
        self.reverse = reverse
    }

    /// Anki's default: by the note's sort field, A to Z.
    public static let `default` = CardSort(column: "noteFld")

    var order: Anki_Search_SortOrder {
        .with { $0.builtin = .with {
            $0.column = column
            $0.reverse = reverse
        } }
    }
}

/// A browser column the cards can be sorted by, named in the core's language.
public struct SortColumn: Identifiable, Hashable, Sendable {
    /// The core's key for the column.
    public let id: String
    public let label: String
    /// Whether choosing this column first sorts it descending, as Anki does
    /// for dates and numbers (newest or largest first).
    public let startsDescending: Bool
}
