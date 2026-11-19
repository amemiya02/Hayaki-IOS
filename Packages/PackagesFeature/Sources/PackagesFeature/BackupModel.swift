import CollectionStore
import Foundation
import Observation

public struct CollectionBackup: Equatable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String { url.lastPathComponent }
    public let date: Date

    fileprivate let url: URL
}

/// The backups for the collection currently open in the app.
@MainActor
@Observable
public final class BackupModel {
    public enum Status: Equatable {
        case idle
        case creating
        case created
        case unchanged
        case failed(String)
    }

    public private(set) var entries: [CollectionBackup] = []
    public private(set) var status: Status = .idle

    @ObservationIgnored private let store: CollectionStore
    @ObservationIgnored private let folder: URL
    @ObservationIgnored private let importer: PackageImportModel
    @ObservationIgnored private var creatingAutomaticBackup = false

    public init(store: CollectionStore, folder: URL, importer: PackageImportModel) {
        self.store = store
        self.folder = folder
        self.importer = importer
    }

    public func loadBackups() {
        do {
            try reload()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    public func createBackup() async {
        guard status != .creating, !creatingAutomaticBackup, !importer.isImporting else { return }
        status = .creating
        do {
            let created = try await store.backUp(to: folder, force: true)
            try reload()
            status = created ? .created : .unchanged
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    public func createAutomaticBackup() async {
        guard status != .creating, !creatingAutomaticBackup, !importer.isImporting else { return }
        creatingAutomaticBackup = true
        defer { creatingAutomaticBackup = false }
        do {
            if try await store.backUp(to: folder, force: false) {
                try reload()
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    public func prepareRestore(_ entry: CollectionBackup) async {
        guard status != .creating, entries.contains(entry) else { return }
        // The common package importer stages the file before asking for
        // replacement, so the pre-restore backup can thin older backups.
        await importer.open(entry.url)
    }

    private func reload() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        let files = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        entries = try files.compactMap { file in
            guard file.pathExtension.lowercased() == "colpkg" else { return nil }
            let values = try file.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
            return CollectionBackup(date: values.contentModificationDate ?? .distantPast, url: file)
        }.sorted { lhs, rhs in
            lhs.date == rhs.date ? lhs.name > rhs.name : lhs.date > rhs.date
        }
    }
}
