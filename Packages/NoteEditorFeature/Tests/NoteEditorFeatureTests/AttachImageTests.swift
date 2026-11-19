import AnkiCore
import AnkiProto
import CollectionStore
import CollectionTesting
import Foundation
import ImageIO
import NoteEditorFeature
import Testing
import UniformTypeIdentifiers

@MainActor
@Suite("Attaching an image", .timeLimit(.minutes(1)))
struct AttachImageTests {
    @Test("An image attached to a field is stored as media and shows on the card")
    func imageShowsOnCard() async throws {
        try await withTemporaryCollection { store in
            let model = NoteEditorModel(store: store)
            await model.load()
            let png = try TestImage.encoded(as: .png)
            model.setText("What colour is this?", ofField: 0)
            model.setText("Red", ofField: 1)

            try await model.attachImage(png, toField: 1)

            let name = try #require(model.fields[1].images.first)
            #expect(name.hasPrefix("paste-") && name.hasSuffix(".png"))
            #expect(TestImage.format(of: try Data(contentsOf: model.mediaFile(named: name))) == .png)

            let outcome = await model.add()
            guard case .added(let added) = outcome else {
                Issue.record("not added: \(outcome)")
                return
            }
            let card = try #require(try await store.core.cardsOfNote(.with { $0.nid = added.noteID }).cids.first)
            let answer = try await store.renderedAnswer(ofCard: card)
            #expect(answer.contains("Red<img src=\"\(name)\">"))
            #expect(FileManager.default.fileExists(atPath: store.location.mediaFolder.appendingPathComponent(name).path))
        }
    }

    @Test("An image can be removed from a field before adding")
    func removeImage() async throws {
        try await withTemporaryCollection { store in
            let model = NoteEditorModel(store: store)
            await model.load()
            model.setText("Front", ofField: 0)
            try await model.attachImage(TestImage.encoded(as: .png), toField: 1)
            let name = try #require(model.fields[1].images.first)

            model.removeImage(named: name, fromField: 1)

            #expect(model.fields[1].images.isEmpty)
            let outcome = await model.add()
            guard case .added(let added) = outcome else {
                Issue.record("not added: \(outcome)")
                return
            }
            #expect(try await store.core.getNote(.with { $0.nid = added.noteID }).fields == ["Front", ""])
        }
    }

    @Test("A field holding only an image is not empty")
    func imageOnlyFirstField() async throws {
        try await withTemporaryCollection { store in
            let model = NoteEditorModel(store: store)
            await model.load()
            try await model.attachImage(TestImage.encoded(as: .png), toField: 0)

            #expect(await model.add().isAdded)
        }
    }

    @Test("An iPhone photo (HEIC) is stored as JPEG, without the place it was taken")
    func heicBecomesJPEGWithoutLocation() async throws {
        try await withTemporaryCollection { store in
            let model = NoteEditorModel(store: store)
            await model.load()
            let heic = try TestImage.encoded(as: .heic, withLocation: true)
            #expect(TestImage.hasLocation(heic))

            try await model.attachImage(heic, toField: 0)

            let name = try #require(model.fields[0].images.first)
            #expect(name.hasSuffix(".jpg"))
            let stored = try Data(contentsOf: model.mediaFile(named: name))
            #expect(TestImage.format(of: stored) == .jpeg)
            #expect(!TestImage.hasLocation(stored))
        }
    }

    @Test("A JPEG keeps its format but loses its location")
    func jpegWithoutLocation() async throws {
        try await withTemporaryCollection { store in
            let model = NoteEditorModel(store: store)
            await model.load()

            try await model.attachImage(TestImage.encoded(as: .jpeg, withLocation: true), toField: 0)

            let name = try #require(model.fields[0].images.first)
            let stored = try Data(contentsOf: model.mediaFile(named: name))
            #expect(TestImage.format(of: stored) == .jpeg)
            #expect(!TestImage.hasLocation(stored))
        }
    }

    @Test("Cropping an attached image replaces its source without changing the field text")
    func cropImage() async throws {
        try await withTemporaryCollection { store in
            let model = NoteEditorModel(store: store)
            await model.load()
            let original = try TestImage.encoded(as: .png)
            model.setText("Front", ofField: 0)
            try await model.attachImage(original, toField: 0)
            let oldName = try #require(model.fields[0].images.first)
            try await model.cropImage(named: oldName, to: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), inField: 0)
            let newName = try #require(model.fields[0].images.first)
            #expect(newName != oldName)
            #expect(model.fields[0].text == "Front")
            let source = try #require(CGImageSourceCreateWithURL(model.mediaFile(named: newName) as CFURL, nil))
            let cropped = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(cropped.width == 4 && cropped.height == 4)
            #expect(await model.add().isAdded)
        }
    }

    @Test("Data that is not an image is refused")
    func notAnImage() async throws {
        try await withTemporaryCollection { store in
            let model = NoteEditorModel(store: store)
            await model.load()

            await #expect(throws: AttachImageError.notAnImage) {
                try await model.attachImage(Data("hello".utf8), toField: 0)
            }
            #expect(model.fields[0].images.isEmpty)
        }
    }
}

extension AddOutcome {
    var isAdded: Bool {
        if case .added = self { true } else { false }
    }
}

extension CollectionStore {
    /// The answer side of a card as the core renders it for studying.
    func renderedAnswer(ofCard card: Int64) async throws -> String {
        let rendered = try await core.renderExistingCard(.with {
            $0.cardID = card
            $0.browser = false
        })
        return rendered.answerNodes.map { node in
            switch node.value {
            case .text(let text): text
            case .replacement(let replacement): replacement.currentText
            case nil: ""
            }
        }.joined()
    }
}

/// Small images made on the fly, as a photo library would hand them over.
enum TestImage {
    static func encoded(as format: UTType, withLocation: Bool = false) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, format.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [:]
        if withLocation {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 35.6812,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 139.7671,
                kCGImagePropertyGPSLongitudeRef: "E",
            ] as [CFString: Any]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return output as Data
    }

    static func format(of data: Data) -> UTType? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { return nil }
        return UTType(type as String)
    }

    static func hasLocation(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return false }
        return properties[kCGImagePropertyGPSDictionary] != nil
    }
}
