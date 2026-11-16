import AnkiCore
import AnkiProto
import CollectionStore

extension CollectionStore {
    /// Adds a filtered deck that borrows up to 100 cards matching an Anki
    /// search, such as `"deck:Spanish"`, as Anki's "Create Filtered Deck"
    /// does. Returns its id.
    @discardableResult
    public func addFilteredDeck(named name: String, search: String) async throws -> Int64 {
        var deck = try await core.getOrCreateFilteredDeck(.with { $0.did = 0 })
        deck.name = name
        deck.config.searchTerms = [.with {
            $0.search = search
            $0.limit = 100
            $0.order = .random
        }]
        return try await modify(.addOrUpdateFilteredDeck(deck)).id
    }
}
