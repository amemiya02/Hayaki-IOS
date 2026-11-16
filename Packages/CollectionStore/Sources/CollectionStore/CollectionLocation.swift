import AnkiProto
import Foundation

/// Where a collection and its media live on disk: one folder holding the
/// collection file, the media folder and the media database, named as Anki
/// names them.
public struct CollectionLocation: Sendable, Equatable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// The app's live collection, in Application Support, which is private to
    /// the app and not shown in the Files app.
    public static func standard(fileManager: FileManager = .default) throws -> CollectionLocation {
        let support = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return CollectionLocation(folder: support.appendingPathComponent("Collection", isDirectory: true))
    }

    public var collectionFile: URL { folder.appendingPathComponent("collection.anki2") }
    public var mediaFolder: URL { folder.appendingPathComponent("collection.media", isDirectory: true) }
    public var mediaDatabase: URL { folder.appendingPathComponent("collection.media.db2") }

    var openRequest: Anki_Collection_OpenCollectionRequest {
        .with {
            $0.collectionPath = collectionFile.path
            $0.mediaFolderPath = mediaFolder.path
            $0.mediaDbPath = mediaDatabase.path
        }
    }
}
