#if DEBUG
import AnkiCore
import CollectionStore
import Foundation

/// Launch support for the app's UI tests (`UITests/`), in debug builds only.
///
/// A UI test sets `HAYAKI_UI_TEST_COLLECTION_PACKAGE` to the path of a
/// collection package. The app then starts from a fresh, throwaway collection
/// made from that package through the core, instead of the learner's own, so
/// every test run sees the same cards. `HAYAKI_UI_TEST_DUE_TODAY`, an Anki
/// search, also makes the matching cards due today.
enum UITestLaunch {
    /// A UI test can keep the same new collection and its own preferences
    /// across launches by passing the same fresh UUID.
    @MainActor
    static var emptyCollectionModel: AppModel? {
        guard
            let argument = ProcessInfo.processInfo.environment["HAYAKI_UI_TEST_EMPTY_COLLECTION"],
            let id = UUID(uuidString: argument),
            let preferences = UserDefaults(suiteName: "HayakiUITests.\(id.uuidString)")
        else { return nil }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("UITestCollection-\(id.uuidString)", isDirectory: true)
        return AppModel(location: { CollectionLocation(folder: folder) }, preferences: preferences)
    }

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
        if let search = ProcessInfo.processInfo.environment["HAYAKI_UI_TEST_DUE_TODAY"] {
            try await makeDueToday(cardsMatching: search, in: location, core: core)
        }
        return location
    }

    /// Makes the cards matching an Anki search due for review today, as
    /// "Set Due Date" with 0 does, so a UI test can study particular cards
    /// whatever the package's scheduling (`HAYAKI_UI_TEST_DUE_TODAY`).
    private static func makeDueToday(cardsMatching search: String, in location: CollectionLocation, core: CoreClient) async throws {
        try await core.openCollection(.with {
            $0.collectionPath = location.collectionFile.path
            $0.mediaFolderPath = location.mediaFolder.path
            $0.mediaDbPath = location.mediaDatabase.path
        })
        let cards = try await core.searchCards(.with { $0.search = search })
        _ = try await core.setDueDate(.with {
            $0.cardIds = cards.ids
            $0.days = "0"
        })
        try await core.closeCollection(.init())
    }
}
#endif
