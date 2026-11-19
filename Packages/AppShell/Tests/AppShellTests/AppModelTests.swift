import AppShell
import CollectionStore
import CollectionTesting
import Foundation
import Testing

@MainActor
@Suite("Launching the app", .timeLimit(.minutes(1)))
struct AppModelTests {
    @Test("The first launch opens a new, empty collection with no setup; the next launch opens the same one")
    func firstAndLaterLaunch() async throws {
        let folder = try TemporaryFolder()
        let location = CollectionLocation(folder: folder.url.appendingPathComponent("Collection"))

        let firstLaunch = AppModel(location: { location }, language: "en")
        await firstLaunch.open()
        let first = try #require(firstLaunch.store)
        #expect(try await first.deckNames() == ["Default"])
        try await first.addDeck(named: "Spanish")
        // The app being terminated.
        try await first.close()

        let laterLaunch = AppModel(location: { location }, language: "en")
        await laterLaunch.open()
        let later = try #require(laterLaunch.store)
        #expect(try await later.deckNames() == ["Default", "Spanish"])
        try await later.close()
    }

    @Test("Starting empty skips Welcome on the next launch, even before creating a deck")
    func startingEmptyCompletesWelcome() async throws {
        let folder = try TemporaryFolder()
        let location = CollectionLocation(folder: folder.url.appendingPathComponent("Collection"))
        let suiteName = UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }

        let first = AppModel(location: { location }, language: "en", preferences: preferences)
        await first.open()
        #expect(first.showsWelcome)
        first.completeWelcome()
        #expect(!first.showsWelcome)
        try await #require(first.store).close()

        let later = AppModel(location: { location }, language: "en", preferences: preferences)
        await later.open()
        #expect(!later.showsWelcome)
        let store = try #require(later.store)
        #expect(try await store.deckNames() == ["Default"])
        try await store.close()
    }

    @Test("When the collection cannot be opened, the app says why instead of crashing")
    func openingFails() async throws {
        let folder = try TemporaryFolder()
        let notAFolder = folder.url.appendingPathComponent("file")
        try Data("not a collection".utf8).write(to: notAFolder)

        let launch = AppModel(location: { CollectionLocation(folder: notAFolder) }, language: "en")
        await launch.open()

        guard case .failed(let message) = launch.state else {
            Issue.record("Expected opening to fail, but the state is \(launch.state)")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test("A startup failure can recover with a collection package and retain the damaged database")
    func recoverAfterOpeningFails() async throws {
        let folder = try TemporaryFolder()
        let location = CollectionLocation(folder: folder.url.appendingPathComponent("Collection", isDirectory: true))
        let backups = folder.url.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: location.folder, withIntermediateDirectories: true)
        let damaged = Data("not valid sqlite".utf8)
        try damaged.write(to: location.collectionFile)
        let model = AppModel(location: { location }, backupFolder: { backups }, language: "en")

        await model.open()

        #expect(model.canRecover)
        #expect(model.store == nil)

        await model.recoverCollection(from: FixturePackage.collection.url)

        let store = try #require(model.store)
        #expect(try await store.contents() == FixturePackage.collection.contents)
        let preserved = try FileManager.default.contentsOfDirectory(
            at: backups.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil
        )
        let preservedFolder = try #require(preserved.first)
        #expect(try Data(contentsOf: preservedFolder.appendingPathComponent("collection.anki2")) == damaged)
        try await store.close()
    }

}
