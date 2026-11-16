import AnkiProto
import Foundation

/// A throwaway collection folder, removed when the test ends.
struct TemporaryCollection: ~Copyable {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("hayaki-core-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    var openRequest: Anki_Collection_OpenCollectionRequest {
        .with {
            $0.collectionPath = folder.appendingPathComponent("collection.anki2").path
            $0.mediaFolderPath = folder.appendingPathComponent("collection.media").path
            $0.mediaDbPath = folder.appendingPathComponent("collection.media.db2").path
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }
}
