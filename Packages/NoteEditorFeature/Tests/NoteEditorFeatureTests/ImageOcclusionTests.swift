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
}
