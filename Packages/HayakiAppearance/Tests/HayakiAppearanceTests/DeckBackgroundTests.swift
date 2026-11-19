import Foundation
import HayakiAppearance
import Testing

struct DeckBackgroundTests {
    @Test func storesAnImagePerCollectionAndKeepsItAfterAFailedReplacement() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pickerImage = folder.appendingPathComponent("photo.png")
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZskkAAAAASUVORK5CYII="))
        try png.write(to: pickerImage)

        let background = DeckBackground(collectionFolder: folder)
        #expect(!background.exists)
        try await background.replace(with: pickerImage)
        try FileManager.default.removeItem(at: pickerImage)
        let reopened = DeckBackground(collectionFolder: folder)
        #expect(reopened.exists)
        #expect(await reopened.image()?.width == 1)
        #expect(await DeckBackground(collectionFolder: folder.appendingPathComponent("other")).image() == nil)

        let corruptFile = folder.appendingPathComponent("corrupt.png")
        try Data("invalid image".utf8).write(to: corruptFile)
        await #expect(throws: CocoaError.self) { try await reopened.replace(with: corruptFile) }
        #expect(await reopened.image()?.height == 1)
        try reopened.remove()
        #expect(await reopened.image() == nil)
    }
}
