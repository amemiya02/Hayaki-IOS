import AppShell
import CollectionStore
import CollectionTesting
import Foundation
import Testing

@MainActor
@Suite("Switching profiles", .timeLimit(.minutes(2)))
struct ProfilesTests {
    @Test("The original collection stays in place and a new profile reopens independently after relaunch")
    func independentCollections() async throws {
        let folder = try TemporaryFolder()
        let legacyLocation = CollectionLocation(folder: folder.url.appendingPathComponent("Collection"))
        let backups = folder.url.appendingPathComponent("Backups")
        let suiteName = "HayakiProfilesTests.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }

        func launch() -> AppModel {
            AppModel(location: { legacyLocation }, backupFolder: { backups }, language: "en", preferences: preferences)
        }

        let original = launch()
        await original.open()
        let legacy = try #require(original.store)
        try await legacy.addDeck(named: "Japanese")
        try await legacy.close()

        let app = launch()
        await app.open()
        let legacyProfile = app.activeProfile
        let upgraded = try #require(app.store)
        #expect(upgraded.location == legacyLocation)
        #expect(try await upgraded.deckNames() == ["Default", "Japanese"])

        let second = try app.addProfile(named: "  French  ")
        #expect(second.name == "French")
        #expect(app.activeProfile == legacyProfile)
        try await app.switchProfile(to: second.id)

        let french = try #require(app.store)
        #expect(try await french.deckNames() == ["Default"])
        let legacyMedia = legacyLocation.mediaFolder.appendingPathComponent("voice.mp3")
        let frenchMedia = french.location.mediaFolder.appendingPathComponent("voice.mp3")
        try Data("Japanese audio".utf8).write(to: legacyMedia)
        try Data("French audio".utf8).write(to: frenchMedia)
        try await french.addDeck(named: "French Verbs")
        try await french.close()

        let restarted = launch()
        await restarted.open()
        #expect(restarted.activeProfile == second)
        let reopened = try #require(restarted.store)
        #expect(try await reopened.deckNames() == ["Default", "French Verbs"])
        #expect(try Data(contentsOf: reopened.location.mediaFolder.appendingPathComponent("voice.mp3")) == Data("French audio".utf8))

        try await restarted.switchProfile(to: legacyProfile.id)
        let returned = try #require(restarted.store)
        #expect(try await returned.deckNames() == ["Default", "Japanese"])
        #expect(try Data(contentsOf: returned.location.mediaFolder.appendingPathComponent("voice.mp3")) == Data("Japanese audio".utf8))
        try await returned.close()
    }
}
