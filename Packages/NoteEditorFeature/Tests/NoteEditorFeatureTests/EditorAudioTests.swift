import AnkiProto
import CollectionStore
import CollectionTesting
import Foundation
import NoteEditorFeature
import Testing

@MainActor
@Suite("Editing field audio", .timeLimit(.minutes(1)))
struct EditorAudioTests {
    @Test("A Files recording remains attached when its field text changes and the saved card exposes replay")
    func importRecording() async throws {
        try await withTemporaryCollection { store in
            let model = NoteEditorModel(store: store)
            await model.load()
            model.setText("Front", ofField: 0)
            let input = store.location.mediaFolder.deletingLastPathComponent().appendingPathComponent("Recording.wav")
            // RIFF/WAVE with four silent signed PCM samples.
            let wave = Data([
                82, 73, 70, 70, 44, 0, 0, 0, 87, 65, 86, 69, 102, 109, 116, 32,
                16, 0, 0, 0, 1, 0, 1, 0, 64, 31, 0, 0, 128, 62, 0, 0, 2, 0,
                16, 0, 100, 97, 116, 97, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            ])
            try wave.write(to: input)
            try await model.importMedia(from: input, toField: 1)
            model.setText("Listen", ofField: 1)
            #expect(model.fields[1].sounds == ["recording.wav"])
            #expect(model.fields[1].text == "Listen")
            guard case .added(let added) = await model.add() else {
                Issue.record("Could not add the note")
                return
            }
            let noteID = added.noteID
            #expect(try await store.core.getNote(.with { $0.nid = noteID }).fields[1] == "Listen[sound:recording.wav]")
            #expect(try Data(contentsOf: model.mediaFile(named: "recording.wav")) == wave)
            let card = try #require(try await store.core.cardsOfNote(.with { $0.nid = noteID }).cids.first)
            let edit = NoteEditorModel(store: store, editingCardID: card)
            await edit.load()
            let preview = try #require(try await edit.preview().first)
            #expect(preview.content.answer.audio.map(\.soundOrVideo) == ["recording.wav"])
        }
    }
}
