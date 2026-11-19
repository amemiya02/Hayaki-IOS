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

    @Test func fieldChangesPreserveNoteValuesAndRefreshCardTemplates() async throws {
        try await withTemporaryCollection { store in
            let model = NoteTypeManager(store: store)
            let id = try await store.core.getNotetypeIdByName(.with { $0.val = "Basic" }).ntid
            let notes = try await store.addNotes(ofType: "Basic", fields: [["harbor", "port"]], toDeck: 1)
            let note = try #require(notes.first)

            #expect(try await model.editFields(of: id, .rename(field: "Front", to: "Term")) == .saved)
            #expect(try await model.editFields(of: id, .add("Example"), confirmingFullSync: true) == .saved)
            #expect(try await model.editFields(of: id, .move(field: "Back", to: 0), confirmingFullSync: true) == .saved)
            #expect(try await model.editFields(of: id, .useForSorting(field: "Example"), confirmingFullSync: true) == .saved)
            #expect(try await model.editFields(of: id, .setKeyboardLanguage(field: "Term", language: "ja-JP")) == .saved)

            let type = try await model.noteType(id)
            #expect(type.fields.map(\.name) == ["Back", "Term", "Example"])
            #expect(type.config.sortFieldIdx == 2)
            #expect(type.templates[0].config.qFormat == "{{Term}}")
            #expect(model.keyboardLanguage(of: type.fields[1]) == "ja-JP")
            #expect(try await store.core.getNote(.with { $0.nid = note }).fields == ["port", "harbor", ""])

            #expect(try await model.editFields(of: id, .delete(field: "Back"), confirmingFullSync: true) == .saved)
            #expect(try await store.core.getNote(.with { $0.nid = note }).fields == ["harbor", ""])
        }
    }
}
