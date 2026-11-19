import AnkiCore
import AnkiProto
import CollectionStore
import CollectionTesting
import Foundation
import NoteEditorFeature
import Testing

@MainActor
@Suite("Image occlusion", .timeLimit(.minutes(1)))
struct ImageOcclusionTests {
    @Test("Adding two masks makes two cards in the chosen deck with shared image media")
    func addMasks() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Diagrams")
            let editor = NoteEditorModel(store: store)
            await editor.load()
            editor.selectDeck(deck)
            try await editor.startImageOcclusion(with: TestImage.encoded(as: .png))
            editor.addOcclusionMask(in: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
            editor.addOcclusionMask(in: CGRect(x: 0.5, y: 0.6, width: 0.2, height: 0.1))
            let outcome = await editor.add()
            guard case .added(let added) = outcome else {
                Issue.record("Expected an image occlusion note, got \(outcome)")
                return
            }
            #expect(added.cardCount == 2)
            let ids = try await store.core.cardsOfNote(.with { $0.nid = added.noteID }).cids
            for id in ids {
                #expect(try await store.core.getCard(.with { $0.cid = id }).deckID == deck)
            }
            let note = try await store.core.getImageOcclusionNote(.with {
                $0.noteID = added.noteID
            }).note
            #expect(note.occlusions.map(\.ordinal).sorted() == [1, 2])
            #expect(note.occlusions.allSatisfy { $0.shapes.map(\.shape) == ["rect"] })
            #expect(!note.imageData.isEmpty)
        }
    }

    @Test("Moving one mask and removing another preserves the remaining card and previews its edited geometry")
    func editMasks() async throws {
        try await withTemporaryCollection { store in
            let editor = NoteEditorModel(store: store)
            await editor.load()
            try await editor.startImageOcclusion(with: TestImage.encoded(as: .png))
            editor.addOcclusionMask(in: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
            editor.addOcclusionMask(in: CGRect(x: 0.5, y: 0.6, width: 0.2, height: 0.1))
            guard case .added(let added) = await editor.add() else {
                Issue.record("Could not create occlusion note")
                return
            }
            let ids = try await store.core.cardsOfNote(.with { $0.nid = added.noteID }).cids
            let first = try #require(ids.first)
            let edit = NoteEditorModel(store: store, editingCardID: first)
            await edit.load()
            #expect(edit.isImageOcclusion)
            let retained = try #require(edit.occlusionMasks.first { $0.ordinal == 1 })
            let deleted = try #require(edit.occlusionMasks.first { $0.ordinal == 2 })
            edit.replaceOcclusionMask(retained.id, with: CGRect(x: 0.25, y: 0.4, width: 0.2, height: 0.2))
            edit.removeOcclusionMask(deleted.id)

            let preview = try await edit.preview()
            #expect(preview.count == 1)
            let question = try #require(preview.first?.content.question.html)
            let answer = try #require(preview.first?.content.answer.html)
            #expect(question.contains("class=\"cloze\"") && question.contains("data-left=\"0.250000\""))
            #expect(answer.contains("class=\"cloze-highlight\""))
            #expect(await edit.save() == .saved)

            let saved = try await store.core.getImageOcclusionNote(.with { $0.noteID = added.noteID }).note
            #expect(saved.occlusions.map(\.ordinal) == [1])
            #expect(try await store.core.getCard(.with { $0.cid = first }).noteID == added.noteID)
        }
    }
}
