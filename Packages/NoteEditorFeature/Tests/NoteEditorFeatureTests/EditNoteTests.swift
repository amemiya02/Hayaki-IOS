import AnkiCore
import AnkiProto
import CollectionStore
import CollectionTesting
import Foundation
import NoteEditorFeature
import Testing

@MainActor
@Suite("Editing a note", .timeLimit(.minutes(1)))
struct EditNoteTests {
    @Test("Edits to a desktop Anki note preserve markup and the untouched field's exact bytes")
    func editsDesktopNote() async throws {
        try await withTemporaryCollection { store in
            let package = try #require(Bundle.module.url(
                forResource: "desktop-markup", withExtension: "apkg", subdirectory: "Fixtures"
            ))
            try await store.modify(.importAnkiPackage(.with { $0.packagePath = package.path }))
            let noteID = try #require(try await store.noteIDs().first)
            let cardIDs = try await store.cardIDs()
            let model = NoteEditorModel(store: store, editingNoteID: noteID)
            await model.load()

            #expect(model.fields.map(\.name) == ["Front", "Back"])
            #expect(model.tags == ["old"])
            model.setMarkup("<b>Very</b> <i>harbor</i>", ofField: 0)
            model.removeTag("old")
            model.addTags("spelling editing")
            #expect(await model.save() == .saved)

            let saved = try await store.core.getNote(.with { $0.nid = noteID })
            #expect(saved.fields[0] == "<b>Very</b> <i>harbor</i>")
            #expect(Array(saved.fields[1].utf8) == Array("<DIV class='keep'>A&nbsp;&amp; B<BR/>Second line</DIV>".utf8))
            #expect(saved.tags == ["editing", "spelling"])
            #expect(try await store.cardIDs() == cardIDs)
        }
    }
}
