import AnkiCore
import AnkiProto
import CollectionStore

/// Setup actions for tests of the card browser.
extension CollectionStore {
    /// Adds one note of the stock Basic note type with the given front and
    /// back and optional tags, and returns the id of its card.
    @discardableResult
    public func addBasicCard(front: String, back: String, inDeck deckID: Int64, tags: [String] = []) async throws -> Int64 {
        let basic = try await core.getNotetypeIdByName(.with { $0.val = "Basic" })
        var note = try await core.newNote(basic)
        note.fields = [front, back]
        note.tags = tags
        let added = try await modify(.addNote(.with {
            $0.note = note
            $0.deckID = deckID
        }))
        return try await core.cardsOfNote(.with { $0.nid = added.noteID }).cids[0]
    }
}
