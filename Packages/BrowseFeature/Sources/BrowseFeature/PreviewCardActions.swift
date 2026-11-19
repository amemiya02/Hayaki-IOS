import AnkiCore
import CollectionStore
import Foundation

@MainActor
enum PreviewCardActions {
    nonisolated static func isMarkTag(_ tag: String) -> Bool {
        tag.caseInsensitiveCompare("marked") == .orderedSame
    }

    static func toggleMark(cardID: Int64, in store: CollectionStore) async throws -> Bool {
        try checkActive(store)
        let card = try await store.core.getCard(.with { $0.cid = cardID })
        try checkActive(store)
        return try await store.toggleNoteMark(card.noteID)
    }

    static func toggleFlag(_ flag: UInt32, cardID: Int64, in store: CollectionStore) async throws -> UInt32 {
        try checkActive(store)
        let card = try await store.core.getCard(.with { $0.cid = cardID })
        try checkActive(store)
        let replacement = (card.flags & 7) == flag ? 0 : flag
        try await store.modify(.setFlag(.with {
            $0.cardIds = [cardID]
            $0.flag = replacement
        }))
        return replacement
    }

    private static func checkActive(_ store: CollectionStore) throws {
        guard store.allowsNewProfileWork else { throw CancellationError() }
    }
}
