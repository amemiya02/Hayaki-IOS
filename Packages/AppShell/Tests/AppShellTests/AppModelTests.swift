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
}
