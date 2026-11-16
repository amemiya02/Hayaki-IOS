import AnkiCore
import AnkiProto
import CollectionStore

extension CollectionStore {
    /// Makes cards review cards that were due `days` days ago and have not
    /// been reviewed since: overdue. Anki's "Set Due Date" cannot set a past
    /// date, so this edits the cards' due day directly through the core.
    public func makeOverdue(byDays days: Int, _ cardIDs: [Int64]) async throws {
        try await makeDueToday(cardIDs)
        var cards: [Anki_Cards_Card] = []
        for id in cardIDs {
            var card = try await core.getCard(.with { $0.cid = id })
            // A review card's due is a day number counted like today's.
            card.due -= Int32(days)
            cards.append(card)
        }
        try await modify(.updateCards(.with { $0.cards = cards }))
    }
}
