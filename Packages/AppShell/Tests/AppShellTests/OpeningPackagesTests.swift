import AppShell
import CollectionStore
import CollectionTesting
import Foundation
import PackagesFeature
import Testing

@MainActor
@Suite("Opening a package from another app", .timeLimit(.minutes(1)))
struct OpeningPackagesTests {
    @Test("A package opened from Files or AirDrop while the app launches starts an import once the collection is open")
    func openedDuringLaunch() async throws {
        let folder = try TemporaryFolder()
        let location = CollectionLocation(folder: folder.url.appendingPathComponent("Collection"))
        let backups = folder.url.appendingPathComponent("Backups")
        let app = AppModel(
            location: { location },
            backupFolder: { backups },
            language: "en"
        )

        await app.openPackage(FixturePackage.basicDeck.url)
        await app.open()

        let packageImport = try #require(app.packageImport)
        guard case .choosingMergeOptions(let package) = packageImport.step else {
            Issue.record("expected the deck package's merge choices, got \(packageImport.step)")
            return
        }
        #expect(package.name == "basic.apkg")
        try await app.store?.close()
    }

    @Test("A package opened while the app is running starts an import")
    func openedWhileRunning() async throws {
        let folder = try TemporaryFolder()
        let location = CollectionLocation(folder: folder.url.appendingPathComponent("Collection"))
        let backups = folder.url.appendingPathComponent("Backups")
        let app = AppModel(
            location: { location },
            backupFolder: { backups },
            language: "en"
        )
        await app.open()

        await app.openPackage(FixturePackage.collection.url)

        let packageImport = try #require(app.packageImport)
        guard case .confirmingReplace = packageImport.step else {
            Issue.record("expected the replace warning, got \(packageImport.step)")
            return
        }
        try await app.store?.close()
    }
}
