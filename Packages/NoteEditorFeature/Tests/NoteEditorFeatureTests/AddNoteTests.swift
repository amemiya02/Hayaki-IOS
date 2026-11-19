import AnkiCore
import AnkiProto
import CollectionStore
import CollectionTesting
import DecksFeature
import NoteEditorFeature
import Testing

@MainActor
@Suite("Adding a note", .timeLimit(.minutes(1)))
struct AddNoteTests {
    @Test("A new collection offers its stock note types and decks, starting with Basic in Default")
    func startsWithBasicInDefault() async throws {
        try await withTemporaryCollection { store in
            let model = NoteEditorModel(store: store)
            await model.load()

            #expect(model.state == .ready)
            #expect(model.notetypeName == "Basic")
            #expect(model.deckName == "Default")
            #expect(model.fields.map(\.name) == ["Front", "Back"])
            #expect(model.fields.map(\.text) == ["", ""])
            #expect(model.notetypes.map(\.name).contains("Cloze"))
            #expect(model.decks.map(\.name) == ["Default"])
        }
    }

    @Test("Image Occlusion is not offered, since its notes are not made of plain fields")
    func noImageOcclusion() async throws {
        try await withTemporaryCollection { store in
            let model = NoteEditorModel(store: store)
            await model.load()

            #expect(!model.notetypes.map(\.name).contains("Image Occlusion"))
        }
    }

    @Test("A basic note becomes one new card in the chosen deck, and the deck list counts it")
    func addBasicNote() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let deckList = DeckListModel(store: store)
            let shown = Task { await deckList.run() }
            defer { shown.cancel() }
            try await eventually("the deck list loaded") { deckList.state == .loaded }

            let model = NoteEditorModel(store: store)
            await model.load()
            model.selectDeck(spanish)
            model.setText("hola", ofField: 0)
            model.setText("hello", ofField: 1)

            let outcome = await model.add()

            #expect(outcome.cardCount == 1)
            let note = try await store.core.getNote(.with { $0.nid = outcome.noteID })
            #expect(note.fields == ["hola", "hello"])
            try await eventually("Spanish counts the new card") {
                deckList.decks.first { $0.name == "Spanish" }?.counts.new == 1
            }
        }
    }

    @Test("Text is stored as Anki stores typed text: special characters escaped, line breaks as <br>")
    func plainTextIsStoredAsHTML() async throws {
        try await withTemporaryCollection { store in
            let model = NoteEditorModel(store: store)
            await model.load()
            model.setText("a < b & c", ofField: 0)
            model.setText("line one\nline two", ofField: 1)

            let outcome = await model.add()

            let note = try await store.core.getNote(.with { $0.nid = outcome.noteID })
            #expect(note.fields == ["a &lt; b &amp; c", "line one<br>line two"])
        }
    }

    @Test("After adding, the fields are empty again while note type, deck and tags stay for the next note")
    func readyForTheNextNote() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let model = NoteEditorModel(store: store)
            await model.load()
            await model.selectNotetype(named: "Basic (and reversed card)")
            model.selectDeck(spanish)
            model.addTags("verbs")
            model.setText("comer", ofField: 0)
            model.setText("to eat", ofField: 1)

            let outcome = await model.add()

            #expect(outcome.cardCount == 2)
            #expect(model.fields.map(\.text) == ["", ""])
            #expect(model.notetypeName == "Basic (and reversed card)")
            #expect(model.deckName == "Spanish")
            #expect(model.tags == ["verbs"])
        }
    }

    @Test("Sticky fields carry their markup into the next note and stay pinned when the editor reopens")
    func repeatsStickyFields() async throws {
        try await withTemporaryCollection { store in
            let editor = NoteEditorModel(store: store)
            await editor.load()
            try await editor.setSticky(true, ofField: 1)
            editor.setText("primero", ofField: 0)
            editor.setMarkup("<i>Spanish</i>", ofField: 1)
            editor.addTags("language")

            #expect(await editor.add().cardCount == 1)
            #expect(editor.fields.map(\.content) == ["", "<i>Spanish</i>"])
            #expect(!editor.hasChanges)

            editor.setText("segundo", ofField: 0)
            let second = await editor.add()
            let note = try await store.core.getNote(.with { $0.nid = second.noteID })
            #expect(note.fields == ["segundo", "<i>Spanish</i>"])
            #expect(note.tags == ["language"])

            let reopened = NoteEditorModel(store: store)
            await reopened.load()
            #expect(reopened.isSticky(1))
            #expect(reopened.fields.map(\.content) == ["", ""])
        }
    }

    @Test("Opening the editor again starts with the note type and deck last used")
    func remembersLastNotetypeAndDeck() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            try await store.addDeck(named: "Geography")
            let first = NoteEditorModel(store: store)
            await first.load()
            await first.selectNotetype(named: "Basic (and reversed card)")
            first.selectDeck(spanish)
            first.setText("comer", ofField: 0)
            first.setText("to eat", ofField: 1)
            #expect(await first.add().cardCount == 2)

            let next = NoteEditorModel(store: store)
            await next.load()

            #expect(next.notetypeName == "Basic (and reversed card)")
            #expect(next.deckName == "Spanish")
            #expect(next.fields.map(\.name) == ["Front", "Back"])
        }
    }

    @Test("Choosing another note type shows its fields and keeps what was typed")
    func switchingNotetype() async throws {
        try await withTemporaryCollection { store in
            let model = NoteEditorModel(store: store)
            await model.load()
            model.setText("{{c1::Madrid}} is the capital of Spain", ofField: 0)

            await model.selectNotetype(named: "Cloze")

            #expect(model.notetypeName == "Cloze")
            #expect(model.fields.map(\.name) == ["Text", "Back Extra"])
            #expect(model.fields.map(\.text) == ["{{c1::Madrid}} is the capital of Spain", ""])
        }
    }

    @Test("A cloze note makes one card per cloze number")
    func addClozeNote() async throws {
        try await withTemporaryCollection { store in
            let model = NoteEditorModel(store: store)
            await model.load()
            await model.selectNotetype(named: "Cloze")
            model.setText("{{c1::Madrid}} is the capital of {{c2::Spain}}", ofField: 0)

            let outcome = await model.add()

            #expect(outcome.cardCount == 2)
        }
    }

    @Test("Tags are added (several at once, separated by spaces), not repeated, and can be removed")
    func tags() async throws {
        try await withTemporaryCollection { store in
            let model = NoteEditorModel(store: store)
            await model.load()

            model.addTags("verbs  spanish::grammar")
            model.addTags("Verbs food")
            #expect(model.tags == ["verbs", "spanish::grammar", "food"])

            model.removeTag("spanish::grammar")
            #expect(model.tags == ["verbs", "food"])

            model.setText("comer", ofField: 0)
            let outcome = await model.add()
            let note = try await store.core.getNote(.with { $0.nid = outcome.noteID })
            // The core keeps a note's tags sorted.
            #expect(note.tags == ["food", "verbs"])
        }
    }

    @Test("A note whose first field is empty is refused, and nothing is added")
    func emptyFirstField() async throws {
        try await withTemporaryCollection { store in
            let model = NoteEditorModel(store: store)
            await model.load()
            model.setText("   ", ofField: 0)
            model.setText("only the back", ofField: 1)

            #expect(await model.add() == .refused(.firstFieldEmpty))
            try #expect(await store.noteCount() == 0)
            #expect(model.fields.map(\.text) == ["   ", "only the back"])
        }
    }

    @Test("A duplicate note is reported, and added only when the learner confirms")
    func duplicate() async throws {
        try await withTemporaryCollection { store in
            let model = NoteEditorModel(store: store)
            await model.load()
            model.setText("hola", ofField: 0)
            #expect(await model.add().cardCount == 1)

            model.setText("hola", ofField: 0)
            model.setText("hi", ofField: 1)
            #expect(await model.add() == .needsConfirmation(.duplicate))
            try #expect(await store.noteCount() == 1)
            #expect(model.fields.map(\.text) == ["hola", "hi"])

            #expect(await model.add(confirming: .duplicate).cardCount == 1)
            try #expect(await store.noteCount() == 2)
        }
    }

    @Test("Cloze mistakes are reported: none in a cloze note, or one outside a cloze note type")
    func clozeChecks() async throws {
        try await withTemporaryCollection { store in
            let model = NoteEditorModel(store: store)
            await model.load()
            model.setText("{{c1::Madrid}}", ofField: 0)
            #expect(await model.add() == .refused(.clozeOutsideClozeNotetype))

            await model.selectNotetype(named: "Cloze")
            model.setText("Madrid", ofField: 0)
            #expect(await model.add() == .needsConfirmation(.noClozeDeletions))

            model.setText("Madrid", ofField: 0)
            model.setText("{{c1::Spain}}", ofField: 1)
            #expect(await model.add() == .refused(.clozeOutsideClozeField))
            try #expect(await store.noteCount() == 0)
        }
    }
}

extension NoteEditorModel {
    func selectNotetype(named name: String) async {
        guard let notetype = notetypes.first(where: { $0.name == name }) else {
            Issue.record("No note type named \(name)")
            return
        }
        await selectNotetype(notetype.id)
    }
}

extension AddOutcome {
    var noteID: Int64 {
        if case .added(let note) = self { note.noteID } else { 0 }
    }

    /// The number of cards the added note made; nil if it was not added.
    var cardCount: Int? {
        if case .added(let note) = self { note.cardCount } else { nil }
    }
}

extension CollectionStore {
    func noteCount() async throws -> Int {
        try await core.searchNotes(.with { $0.search = "" }).ids.count
    }
}
