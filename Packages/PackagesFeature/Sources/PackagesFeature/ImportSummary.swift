import AnkiProto
import Foundation

/// What an import did, shown to the learner when it finishes.
public enum ImportSummary: Sendable, Equatable {
    /// A collection package replaced the collection.
    case replaced(ReplaceResult)
    /// A deck package was merged into the collection.
    case merged(MergeResult)
}

/// The collection a collection package brought in.
public struct ReplaceResult: Sendable, Equatable {
    public let decks: Int
    public let notes: Int
    public let cards: Int
    /// Whether a backup of the previous collection was made first. The core
    /// skips it when nothing changed since the last backup, which then holds
    /// the same collection.
    public let backupMade: Bool

    public init(decks: Int, notes: Int, cards: Int, backupMade: Bool) {
        self.decks = decks
        self.notes = notes
        self.cards = cards
        self.backupMade = backupMade
    }
}

/// What a deck package merge did with each note in the package. Notes are
/// listed by their first field as plain text.
public struct MergeResult: Sendable, Equatable {
    /// Notes new to the collection, added with their cards.
    public let added: [String]
    /// Notes already in the collection whose content the package replaced.
    public let updated: [String]
    /// Notes already in the collection that were left as they were, because
    /// the update choice did not allow replacing them.
    public let unchanged: [String]
    /// Notes skipped because the collection's copy has a different note type.
    public let conflicting: [String]

    /// Notes the import did not add or change.
    public var skipped: [String] { unchanged + conflicting }

    init(_ log: Anki_ImportExport_ImportResponse.Log) {
        added = log.new.map(\.summaryText)
        updated = log.updated.map(\.summaryText)
        unchanged = log.duplicate.map(\.summaryText)
        conflicting = log.conflicting.map(\.summaryText)
    }
}

private extension Anki_ImportExport_ImportResponse.Note {
    /// The first field without markup, as Anki's import log shows it.
    var summaryText: String {
        guard let first = fields.first else { return "" }
        let withoutTags = first.replacing(/<[^>]*>/, with: " ")
            .replacing(/\[sound:[^\]]*\]/, with: " ")
        let decoded = withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
        return decoded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
