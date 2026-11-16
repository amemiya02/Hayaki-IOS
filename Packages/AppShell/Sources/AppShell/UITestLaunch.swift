#if DEBUG
import AnkiCore
import CollectionStore
import Foundation

/// Launch support for the app's UI tests (`UITests/`), in debug builds only.
///
/// A UI test sets `HAYAKI_UI_TEST_COLLECTION_PACKAGE` to the path of a
/// collection package. The app then starts from a fresh, throwaway collection
/// made from that package through the core, instead of the learner's own, so
/// every test run sees the same cards.
enum UITestLaunch {
    static var collectionPackage: URL? {
        ProcessInfo.processInfo.environment["HAYAKI_UI_TEST_COLLECTION_PACKAGE"].map {
            URL(fileURLWithPath: $0)
        }
    }

    /// Makes a throwaway collection in the temporary folder from `package`.
    static func collection(from package: URL, core: CoreClient) async throws -> CollectionLocation {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("UITestCollection", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        let location = CollectionLocation(folder: folder)
        try FileManager.default.createDirectory(at: location.mediaFolder, withIntermediateDirectories: true)
        try await core.importCollectionPackage(.with {
            $0.colPath = location.collectionFile.path
            $0.backupPath = package.path
            $0.mediaFolder = location.mediaFolder.path
            $0.mediaDb = location.mediaDatabase.path
        })
        return location
    }
}
#endif
