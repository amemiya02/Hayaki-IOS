@testable import BrowseFeature
import CollectionTesting
import Testing

@MainActor
@Suite("Browse preview actions")
struct PreviewCardActionsTests {
    @Test("Preview mark and flag are undoable collection changes and leave scheduling untouched")
    func isolatedActions() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Preview")
            let cards = try await store.addBasicNotes(count: 2, toDeck: deck)
            let target = try #require(cards.first)
            let other = try #require(cards.last)
            let card = try await store.core.getCard(.with { $0.cid = target })
            let noteID = card.noteID

            _ = try await store.modify(.addNoteTags(.with {
                $0.noteIds = [noteID]
                $0.tags = "marked::custom"
            }))
            #expect(try await PreviewCardActions.toggleMark(cardID: target, in: store))
            let marked = try await store.core.getNote(.with { $0.nid = noteID })
            #expect(Set(marked.tags) == ["marked", "marked::custom"])
            let unmarked = try await PreviewCardActions.toggleMark(cardID: target, in: store)
            #expect(!unmarked)
            #expect(try await store.core.getNote(.with { $0.nid = noteID }).tags == ["marked::custom"])

            #expect(try await PreviewCardActions.toggleFlag(7, cardID: target, in: store) == 7)
            #expect(try await PreviewCardActions.toggleFlag(7, cardID: target, in: store) == 0)
            _ = try await store.undo()
            #expect(try await store.core.getCard(.with { $0.cid = target }).flags == 7)
            #expect(try await store.core.getCard(.with { $0.cid = other }).flags == 0)
            #expect(try await store.reviewCount() == 0)
        }
    }
}
