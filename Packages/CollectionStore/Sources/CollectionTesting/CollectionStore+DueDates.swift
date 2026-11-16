import AnkiCore
import AnkiProto
import CollectionStore

extension CollectionStore {
    /// Makes cards review cards due `days` days from today, as Anki's "Set
    /// Due Date" does.
    public func makeDue(inDays days: Int, _ cardIDs: [Int64]) async throws {
        try await modify(.setDueDate(.with {
            $0.cardIds = cardIDs
            $0.days = String(days)
        }))
    }
}
