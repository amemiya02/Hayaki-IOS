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

    @Test("A file received during a profile switch opens in the incoming profile")
    func openedDuringSwitch() async throws {
        let folder = try TemporaryFolder()
        let location = CollectionLocation(folder: folder.url.appendingPathComponent("Collection"))
        let backup = folder.url.appendingPathComponent("Backups")
        let domain = "dev.hayaki.OpeningPackages.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let app = AppModel(location: { location }, backupFolder: { backup }, language: "en", preferences: preferences)
        await app.open()
        let oldImporter = try #require(app.packageImport)
        let incoming = try app.addProfile(named: "Incoming")

        let switching = Task { try await app.switchProfile(to: incoming.id) }
        while !app.isSwitchingProfile && app.activeProfile != incoming { await Task.yield() }
        try #require(app.isSwitchingProfile)
        await app.openPackage(FixturePackage.basicDeck.url)
        try await switching.value

        #expect(oldImporter.step == .idle)
        #expect(app.activeProfile == incoming)
        let newImporter = try #require(app.packageImport)
        guard case .choosingMergeOptions(let package) = newImporter.step else {
            Issue.record("Expected merge choices in the incoming profile, got \(newImporter.step)")
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

@MainActor
@Suite("Opening text files")
struct OpeningTextFilesTests {
    @Test("Files text import queues during launch and its selection stays with the original profile")
    func openedDuringLaunch() async throws {
        let folder = try TemporaryFolder()
        let location = CollectionLocation(folder: folder.url.appendingPathComponent("Collection"))
        let backups = folder.url.appendingPathComponent("Backups")
        let domain = "dev.hayaki.OpeningTextFiles.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let app = AppModel(
            location: { location },
            backupFolder: { backups },
            language: "en",
            preferences: preferences
        )
        let source = folder.url.appendingPathComponent("new notes.CSV")
        try "Front,Back\nHello,World\n".write(to: source, atomically: true, encoding: .utf8)

        await app.openPackage(source)
        await app.open()

        let original = try #require(app.textImport)
        let originalStore = try #require(app.store)
        #expect(original.isPresented)
        #expect(original.fileName == "new notes.CSV")
        #expect(original.metadata != nil)
        #expect(app.packageImport?.step == .idle)

        let other = try app.addProfile(named: "Other")
        try await app.switchProfile(to: other.id)
        await original.prepare(source)
        await original.startImport()
        let current = try #require(app.textImport)
        let currentStore = try #require(app.store)

        #expect(!originalStore.allowsNewProfileWork)
        #expect(!original.isPresented)
        #expect(original.metadata == nil)
        #expect(original.summary == nil)
        #expect(current !== original)
        #expect(current.fileName == nil)
        let before = try await currentStore.snapshot()
        #expect(before.notes.isEmpty)

        await app.openPackage(source)
        #expect(current.isPresented)
        #expect(current.fileName == "new notes.CSV")
        await current.startImport()
        let after = try await currentStore.snapshot()
        #expect(after.notes.contains { $0.fields == ["Hello", "World"] })
        try await currentStore.close()
    }
}
