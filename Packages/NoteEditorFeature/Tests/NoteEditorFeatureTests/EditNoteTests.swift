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
            // Exported by Anki 26.09.4's desktop Python collection API.
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

    @Test("A new empty first field is refused and a duplicate requires confirmation")
    func checksEditsBeforeSaving() async throws {
        try await withTemporaryCollection { store in
            let ids = try await store.addNotes(ofType: "Basic", fields: [["Old", "Back"], ["Taken", "Answer"]], toDeck: 1)
            let id = try #require(ids.first)
            let model = NoteEditorModel(store: store, editingNoteID: id)
            await model.load()

            model.setText(" ", ofField: 0)
            #expect(await model.save() == .refused(.firstFieldEmpty))
            model.setText("Taken", ofField: 0)
            #expect(await model.save() == .needsConfirmation(.duplicate))
            #expect(try await store.core.getNote(.with { $0.nid = id }).fields[0] == "Old")

            #expect(await model.save(confirming: .duplicate) == .saved)
            #expect(try await store.core.getNote(.with { $0.nid = id }).fields[0] == "Taken")
        }
    }

    @Test("Deleting an edited note removes all its cards")
    func deletesNoteAndItsCards() async throws {
        try await withTemporaryCollection { store in
            let ids = try await store.addNotes(
                ofType: "Basic (and reversed card)", fields: [["front", "back"]], toDeck: 1
            )
            let id = try #require(ids.first)
            #expect(try await store.cardIDs().count == 2)
            let model = NoteEditorModel(store: store, editingNoteID: id)
            await model.load()

            try await model.delete()

            #expect(try await store.noteIDs().isEmpty)
            #expect(try await store.cardIDs().isEmpty)
        }
    }

    @Test("Preview renders both sides of the unsaved draft and leaves the saved note alone")
    func previewsTheDraft() async throws {
        try await withTemporaryCollection { store in
            let notes = try await store.addNotes(
                ofType: "Basic (and reversed card)", fields: [["Before", "Other side"]], toDeck: 1
            )
            let noteID = try #require(notes.first)
            let model = NoteEditorModel(store: store, editingNoteID: noteID)
            await model.load()
            model.setMarkup("<b>After</b>", ofField: 0)

            let cards = try await model.preview()
            #expect(cards.map(\.name) == ["Card 1", "Card 2"])
            #expect(cards[0].content.question.html.contains("<b>After</b>"))
            #expect(cards[0].content.answer.html.contains("Other side"))
            #expect(cards[1].content.question.html.contains("Other side"))
            #expect(cards[1].content.answer.html.contains("<b>After</b>"))
            #expect(try await store.core.getNote(.with { $0.nid = noteID }).fields[0] == "Before")
        }
    }

    @Test("Preview can show a new cloze on an existing note")
    func previewsNewCloze() async throws {
        try await withTemporaryCollection { store in
            let notes = try await store.addNotes(ofType: "Cloze", fields: [["{{c1::Paris}}", "City"]], toDeck: 1)
            let model = NoteEditorModel(store: store, editingNoteID: try #require(notes.first))
            await model.load()
            model.setText("{{c1::Paris}} and {{c3::Rome}}", ofField: 0)

            let cards = try await model.preview()

            #expect(cards.map(\.id) == [0, 2])
            #expect(cards[1].content.question.html.contains("Paris"))
            #expect(cards[1].content.question.html.contains(#"data-ordinal="3">[...]</span>"#))
            #expect(cards[1].content.answer.html.contains(#"data-ordinal="3">Rome</span>"#))
            #expect(try await store.cardIDs().count == 1)
        }
    }
}
