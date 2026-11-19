import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Observation

@MainActor
@Observable
public final class CollectionMaintenanceModel {
    public struct MediaReport: Equatable, Sendable {
        public let missing: [String]
        public let unused: [String]
        public let hasTrash: Bool

        init(_ report: Anki_Media_CheckMediaResponse) {
            missing = report.missing.sorted()
            unused = report.unused.sorted()
            hasTrash = report.haveTrash
        }
    }

    public struct StorageUsage: Equatable, Sendable {
        public let database: Int64
        public let media: Int64
    }

    public private(set) var isRunning = false
    public private(set) var error: String?
    public private(set) var media: MediaReport?
    public private(set) var databaseProblems: [String]?
    public private(set) var storageUsage: StorageUsage?

    @ObservationIgnored private let store: CollectionStore

    public init(store: CollectionStore) {
        self.store = store
    }

    public func checkMedia() async {
        await run {
            try await reloadMedia()
        }
    }

    public func trashUnusedMedia() async {
        guard let reviewed = media?.unused, !reviewed.isEmpty else { return }
        await run {
            // A learner may have added a reference since the first check.
            let current = try await store.core.checkMedia()
            let names = current.unused.filter(Set(reviewed).contains)
            if !names.isEmpty {
                try await store.core.trashMediaFiles(.with { $0.fnames = names })
                store.signal(.everything)
            }
            try await reloadMedia()
        }
    }

    public func restoreMediaTrash() async {
        guard media?.hasTrash == true else { return }
        await run {
            try await store.core.restoreTrash()
            store.signal(.everything)
            try await reloadMedia()
        }
    }

    public func emptyMediaTrash() async {
        guard media?.hasTrash == true else { return }
        await run {
            try await store.core.emptyTrash()
            try await reloadMedia()
        }
    }

    public func checkDatabase() async {
        await run {
            databaseProblems = try await store.core.checkDatabase().problems
            store.signal(.everything)
        }
    }

    public func loadStorageUsage() async {
        let location = store.location
        storageUsage = await Task.detached(priority: .utility) {
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
            let database = (try? location.collectionFile.resourceValues(forKeys: keys).fileSize) ?? 0
            let files = FileManager.default.enumerator(
                at: location.mediaFolder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
            )
            var mediaBytes: Int64 = 0
            while let file = files?.nextObject() as? URL {
                guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
                mediaBytes += Int64(values.fileSize ?? 0)
            }
            return StorageUsage(database: Int64(database), media: mediaBytes)
        }.value
    }

    private func reloadMedia() async throws {
        media = try await MediaReport(store.core.checkMedia())
        await loadStorageUsage()
    }

    private func run(_ work: () async throws -> Void) async {
        guard !isRunning else { return }
        isRunning = true
        error = nil
        defer { isRunning = false }
        do {
            try await work()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
