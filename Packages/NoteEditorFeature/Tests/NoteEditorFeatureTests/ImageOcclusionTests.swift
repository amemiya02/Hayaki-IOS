import AnkiCore
import AnkiProto
import CollectionStore
import CollectionTesting
import Foundation
import ImageIO
import NoteEditorFeature
import StudyFeature
import Testing
import UniformTypeIdentifiers

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

    @Test("An image occlusion deck package keeps the shared image and is reviewable after import")
    func exportMasks() async throws {
        let generated = ProcessInfo.processInfo.environment["HAYAKI_IMAGE_OCCLUSION_FIXTURE"]
            .map { URL(fileURLWithPath: $0) }
        let package = generated ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("apkg")
        defer {
            if generated == nil { try? FileManager.default.removeItem(at: package) }
        }
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Image Occlusion Parity")
            let editor = NoteEditorModel(store: store)
            await editor.load()
            editor.selectDeck(deck)
            try await editor.startImageOcclusion(with: diagram())
            editor.addOcclusionMask(in: CGRect(x: 0.08, y: 0.12, width: 0.24, height: 0.36))
            editor.addOcclusionMask(in: CGRect(x: 0.59, y: 0.55, width: 0.3, height: 0.34), ellipse: true)
            editor.setOccludesInactiveMasks(true)
            editor.setText("Recall the masked color", ofField: 2)
            editor.setText("Red and blue", ofField: 3)
            let preview = try await editor.preview()
            #expect(preview.count == 2)
            let pendingFiles = try FileManager.default.contentsOfDirectory(atPath: store.location.mediaFolder.path)
            #expect(pendingFiles.isEmpty)
            guard case .added(let added) = await editor.add() else {
                Issue.record("Could not create the fixture note")
                return
            }
            #expect(added.cardCount == 2)
            let exported = try await store.core.exportAnkiPackage(.with {
                $0.outPath = package.path
                $0.options.withMedia = true
                $0.options.withScheduling = true
                $0.limit.deckID = deck
            })
            #expect(exported.val == 1)
        }

        try await withTemporaryCollection { store in
            _ = try await store.modify(.importAnkiPackage(.with { $0.packagePath = package.path }))
            let id = try #require(try await store.noteIDs().first)
            let imported = try await store.core.getImageOcclusionNote(.with { $0.noteID = id }).note
            #expect(imported.occlusions.flatMap(\.shapes).map(\.shape).sorted() == ["ellipse", "rect"])
            #expect(imported.header == "Recall the masked color")
            #expect(imported.backExtra == "Red and blue")
            #expect(imported.occludeInactive)
            #expect(!imported.imageData.isEmpty)
            #expect(try Data(contentsOf: store.location.mediaFolder.appendingPathComponent(imported.imageFileName)) == imported.imageData)

            let names = try await store.core.getDeckNames(.with { $0.skipEmptyDefault = true }).entries
            let deck = try #require(names.first { $0.name == "Image Occlusion Parity" }?.id)
            let study = StudySessionModel(store: store, deckID: deck)
            await study.start()
            let question = try #require(study.state.question)
            #expect(question.question.html.contains(imported.imageFileName))
            #expect(question.question.html.contains("data-occludeInactive=\"1\""))
            study.showAnswer()
            #expect(study.state.answer?.answer.html.contains("class=\"cloze-highlight\"") == true)
            await study.answer(.easy)
            #expect(study.reviewedCount == 1)
        }
    }

    private func diagram() throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        context.setFillColor(red: 0.75, green: 0.07, blue: 0.18, alpha: 1)
        context.fill(CGRect(x: 64, y: 260, width: 124, height: 130))
        context.setFillColor(red: 0.08, green: 0.35, blue: 0.77, alpha: 1)
        context.fillEllipse(in: CGRect(x: 400, y: 80, width: 128, height: 118))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let encoder = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, image, nil)
        try #require(CGImageDestinationFinalize(encoder))
        return data as Data
    }
}
