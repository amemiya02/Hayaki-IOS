import AnkiCore
import CollectionStore
import Foundation

/// A folder in the temporary directory, removed when the value goes away.
public struct TemporaryFolder: ~Copyable {
    public let url: URL

    public init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hayaki-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Runs `body` with a fresh, empty collection opened in a temporary folder by
/// a real Core Client, then closes the collection and removes the folder.
///
///     try await withTemporaryCollection { store in
///         let model = DeckListModel(store: store)
///         ...
///     }
public func withTemporaryCollection<Result>(
    language: String = "en",
    isolation: isolated (any Actor)? = #isolation,
    _ body: (CollectionStore) async throws -> Result
) async throws -> Result {
    let folder = try TemporaryFolder()
    let location = CollectionLocation(folder: folder.url.appendingPathComponent("Collection", isDirectory: true))
    let store = try await CollectionStore.open(at: location, core: CoreClient(language: language))
    let result: Result
    do {
        result = try await body(store)
    } catch {
        try? await store.close()
        throw error
    }
    try await store.close()
    return result
}
