import CollectionTesting
import Foundation
import PackagesFeature
import Testing

@MainActor
@Suite("Backups")
struct BackupTests {
    @Test("A manual backup can be selected for a confirmed restore after a relaunch")
    func backupAndRestore() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            try await store.addBasicNotes(count: 1, toDeck: deck)
            let expected = try await store.snapshot()
            let folder = try TemporaryFolder()
            let importer = PackageImportModel(store: store, backupFolder: folder.url)
            let backups = BackupModel(store: store, folder: folder.url, importer: importer)

            await backups.createBackup()

            let backup = try #require(backups.entries.first)
            #expect(backup.name.hasSuffix(".colpkg"))
            try await store.addBasicNotes(count: 2, toDeck: deck)
            let reopened = BackupModel(store: store, folder: folder.url, importer: importer)
            reopened.loadBackups()
            #expect(reopened.entries.map(\.name) == [backup.name])
            await reopened.prepareRestore(backup)
            guard case .confirmingReplace = importer.step else {
                Issue.record("The backup did not open the replacement confirmation")
                return
            }
            #expect(try await store.snapshot() != expected)

            await importer.startImport()

            #expect(try await store.snapshot() == expected)
        }
    }
}
