import AnkiCore
import CollectionStore

extension CollectionStore {
    /// How many cards match an Anki search, such as `"deck:Spanish"`; an
    /// empty search matches every card in the collection.
    public func cardCount(matching search: String) async throws -> Int {
        try await core.searchCards(.with { $0.search = search }).ids.count
    }
}
