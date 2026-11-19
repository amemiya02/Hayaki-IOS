import AnkiCore
import AnkiProto
import CollectionStore
import Foundation

public enum NoteTypeSaveResult: Equatable, Sendable {
    case saved
    case needsFullSyncConfirmation
}

public enum NoteTypeFieldAction: Sendable {
    case add(String)
    case rename(field: String, to: String)
    case move(field: String, to: Int)
    case useForSorting(field: String)
    case setKeyboardLanguage(field: String, language: String?)
    case delete(field: String)
}

extension NoteTypeManager {
    public func editFields(
        of id: Int64,
        _ action: NoteTypeFieldAction,
        confirmingFullSync: Bool = false
    ) async throws(CoreError) -> NoteTypeSaveResult {
        let current = try await noteType(id)
        var type = current
        let changesSchema: Bool
        switch action {
        case .add(let name):
            let name = try fieldName(name, in: type)
            type.fields.append(.with {
                $0.name = name
                $0.config.fontName = "Arial"
                $0.config.fontSize = 20
            })
            changesSchema = true
        case .rename(let field, let name):
            let index = try fieldIndex(field, in: type)
            type.fields[index].name = try fieldName(name, in: type, excluding: index)
            changesSchema = false
        case .move(let field, let position):
            let index = try fieldIndex(field, in: type)
            guard type.fields.indices.contains(position) else {
                throw CoreError(kind: .invalidInput, message: String(localized: "Choose an existing field position.", bundle: .module))
            }
            let moved = type.fields.remove(at: index)
            type.fields.insert(moved, at: position)
            changesSchema = true
        case .useForSorting(let field):
            let index = try fieldIndex(field, in: type)
            type.config.sortFieldIdx = type.fields[index].ord.val
            changesSchema = true
        case .setKeyboardLanguage(let field, let language):
            let index = try fieldIndex(field, in: type)
            try setKeyboardLanguage(language, on: &type.fields[index])
            changesSchema = false
        case .delete(let field):
            let index = try fieldIndex(field, in: type)
            guard type.fields.count > 1, !type.fields[index].config.preventDeletion else {
                throw CoreError(kind: .invalidInput, message: String(localized: "This field is required.", bundle: .module))
            }
            type.fields.remove(at: index)
            changesSchema = true
        }
        guard type != current else { return .saved }
        if changesSchema, try await store.requiresSchemaConfirmation(confirmed: confirmingFullSync) {
            return .needsFullSyncConfirmation
        }
        try await store.modify(.updateNotetype(type))
        return .saved
    }

    public func delete(_ id: Int64, confirmingFullSync: Bool = false) async throws(CoreError) -> NoteTypeSaveResult {
        guard try await entries().count > 1 else {
            throw CoreError(kind: .invalidInput, message: String(localized: "Keep at least one note type.", bundle: .module))
        }
        if try await store.requiresSchemaConfirmation(confirmed: confirmingFullSync) {
            return .needsFullSyncConfirmation
        }
        try await store.modify(.removeNotetype(.with { $0.ntid = id }))
        return .saved
    }

    public func keyboardLanguage(of field: Anki_Notetypes_Notetype.Field) -> String? {
        guard !field.config.other.isEmpty else { return nil }
        let other = try? JSONSerialization.jsonObject(with: field.config.other) as? [String: Any]
        return other?["ad-hint-locale"] as? String
    }

    private func setKeyboardLanguage(
        _ language: String?,
        on field: inout Anki_Notetypes_Notetype.Field
    ) throws(CoreError) {
        var other: [String: Any] = [:]
        do {
            if !field.config.other.isEmpty {
                guard let saved = try JSONSerialization.jsonObject(with: field.config.other) as? [String: Any] else {
                    throw CocoaError(.coderReadCorrupt)
                }
                other = saved
            }
            other["ad-hint-locale"] = language
            field.config.other = other.isEmpty ? Data() : try JSONSerialization.data(withJSONObject: other, options: [.sortedKeys])
        } catch {
            throw CoreError(kind: .protoError, message: error.localizedDescription)
        }
    }

    private func fieldIndex(
        _ name: String,
        in type: Anki_Notetypes_Notetype
    ) throws(CoreError) -> Int {
        guard let index = type.fields.firstIndex(where: { $0.name == name }) else {
            throw CoreError(kind: .notFoundError, message: String(localized: "This field is no longer in the note type.", bundle: .module))
        }
        return index
    }

    private func fieldName(
        _ input: String,
        in type: Anki_Notetypes_Notetype,
        excluding index: Int? = nil
    ) throws(CoreError) -> String {
        let cleaned = input.filter { !"\n\r{}:\"".contains($0) }
        let name = String(cleaned.drop(while: { "#^/ \t".contains($0) })).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw CoreError(kind: .invalidInput, message: String(localized: "Enter a field name.", bundle: .module))
        }
        if type.fields.enumerated().contains(where: {
            $0.offset != index && $0.element.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            throw CoreError(kind: .invalidInput, message: String(localized: "A field already has that name.", bundle: .module))
        }
        return name
    }
}

extension CollectionStore {
    func requiresSchemaConfirmation(confirmed: Bool = false) async throws(CoreError) -> Bool {
        guard !confirmed else { return false }
        // Same local schema and last-sync timestamps Android uses. The
        // core's DB proxy runs the fixed read on the open collection.
        let query = #"{"kind":"query","sql":"select scm > ls from col","args":[],"first_row_only":true}"#
        let response = try await core.runDbCommandProto(.with { $0.json = Data(query.utf8) })
        guard case .longValue(let alreadyChanged)? = response.result.rows.first?.fields.first?.data else {
            throw CoreError(kind: .protoError, message: String(localized: "Could not read the collection’s sync status.", bundle: .module))
        }
        return alreadyChanged == 0
    }
}
