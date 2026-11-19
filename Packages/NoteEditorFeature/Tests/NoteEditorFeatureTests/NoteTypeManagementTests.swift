import AnkiCore
import AnkiProto
import CollectionTesting
import NoteEditorFeature
import Testing

@MainActor
struct NoteTypeManagementTests {
    @Test func learnerCanAddCloneAndRenameNoteTypes() async throws {
        try await withTemporaryCollection { store in
            let model = NoteTypeManager(store: store)
            let original = try await store.core.getNotetypeIdByName(.with { $0.val = "Basic" })
            let copy = try await model.add(named: "Vocabulary", from: .existing(original.ntid))
            let stock = try await model.add(named: "Recall Both Ways", from: .stock(.basicAndReversed))
            try await model.rename(copy, to: "Phrases")

            let entries = try await model.entries()
            #expect(entries.first { $0.id == copy }?.name == "Phrases")
            #expect(entries.first { $0.id == original.ntid }?.name == "Basic")
            #expect(entries.first { $0.id == stock }?.name == "Recall Both Ways")
            let types = try await (model.noteType(copy), model.noteType(stock))
            #expect(types.0.fields.map(\.name) == ["Front", "Back"])
            #expect(types.1.templates.count == 2)
        }
    }
}
