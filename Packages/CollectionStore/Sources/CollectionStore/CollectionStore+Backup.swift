import AnkiCore
import Foundation

extension CollectionStore {
    /// Saves a backup through Anki's core and waits for the file to be written.
    /// Returns false when the collection hasn't changed or it was backed up
    /// within the configured interval. Manual backups bypass the interval.
    @discardableResult
    public func backUp(to folder: URL, force: Bool) async throws -> Bool {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try await core.createBackup(.with {
            $0.backupFolder = folder.path
            $0.force = force
            $0.waitForCompletion = true
        }).val
    }
}
