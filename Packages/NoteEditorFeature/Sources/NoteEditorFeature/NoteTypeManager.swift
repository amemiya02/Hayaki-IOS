import AnkiCore
import AnkiProto
import CollectionStore
import Foundation

public struct ManagedNoteType: Identifiable, Sendable {
    public let id: Int64
    public let name: String
    public let noteCount: UInt32
}

public enum NoteTypeSource: Hashable, Sendable {
    case stock(Anki_Notetypes_StockNotetype.Kind)
    case existing(Int64)
}

/// Access to note types and their definitions in the open collection.
@MainActor
public struct NoteTypeManager {
    let store: CollectionStore

    public init(store: CollectionStore) {
        self.store = store
    }

    public func entries() async throws(CoreError) -> [ManagedNoteType] {
        try await store.core.getNotetypeNamesAndCounts().entries.map {
            ManagedNoteType(id: $0.id, name: $0.name, noteCount: $0.useCount)
        }
    }

    public func noteType(_ id: Int64) async throws(CoreError) -> Anki_Notetypes_Notetype {
        try await store.core.getNotetype(.with { $0.ntid = id })
    }

    @discardableResult
    public func add(named name: String, from source: NoteTypeSource) async throws(CoreError) -> Int64 {
        let name = try await availableName(name)
        switch source {
        case .existing(let id):
            var copy = try await noteType(id)
            copy.id = 0
            copy.name = name
            return try await store.modify(.addNotetype(copy)).id
        case .stock(let kind):
            let stock = try await store.core.getStockNotetypeLegacy(.with { $0.kind = kind })
            let json: Data
            do {
                guard var definition = try JSONSerialization.jsonObject(with: stock.json) as? [String: Any] else {
                    throw CocoaError(.coderReadCorrupt)
                }
                definition["name"] = name
                json = try JSONSerialization.data(withJSONObject: definition)
            } catch {
                throw CoreError(kind: .protoError, message: error.localizedDescription)
            }
            return try await store.modify(.addNotetypeLegacy(.with { $0.json = json })).id
        }
    }

    public func rename(_ id: Int64, to name: String) async throws(CoreError) {
        let name = try await availableName(name, excluding: id)
        var type = try await noteType(id)
        guard type.name != name else { return }
        type.name = name
        try await store.modify(.updateNotetype(type))
    }

    private func availableName(_ input: String, excluding id: Int64? = nil) async throws(CoreError) -> String {
        let name = input.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw CoreError(kind: .invalidInput, message: String(localized: "Enter a note type name.", bundle: .module))
        }
        if try await entries().contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            throw CoreError(kind: .invalidInput, message: String(localized: "A note type already has that name.", bundle: .module))
        }
        return name
    }
}
