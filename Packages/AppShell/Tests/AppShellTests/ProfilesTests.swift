import AppShell
import CollectionStore
import CollectionTesting
import Foundation
import PackagesFeature
import Synchronization
import SyncFeature
import SyncTesting
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

    @Test("Sync sign-ins, pending uploads, staged imports, and backups stay with the profile that owns them",
          .enabled(if: SyncServer.isBuilt, SyncServer.skipMessage))
    func workStaysInItsProfile() async throws {
        let firstServer = try await SyncServer(users: [("alice", "first password")])
        let secondServer = try await SyncServer(users: [("bob", "second password")])
        let folder = try TemporaryFolder()
        let location = CollectionLocation(folder: folder.url.appendingPathComponent("Collection"))
        let backupFolder = folder.url.appendingPathComponent("Backups")
        let suite = "HayakiProfilesTests.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let legacyKeychainItem = ProfileTestAccount()
        let secondKeychainItem = ProfileTestAccount()

        func launch() -> AppModel {
            AppModel(
                location: { location }, backupFolder: { backupFolder }, language: "en",
                preferences: preferences,
                accountStorage: { profileID in profileID == nil ? legacyKeychainItem : secondKeychainItem }
            )
        }

        let upgraded = launch()
        await upgraded.open()
        let defaultID = upgraded.activeProfile.id
        let legacyStore = try #require(upgraded.store)
        try await legacyStore.addBasicNotes(count: 1, toDeck: legacyStore.addDeck(named: "Private"))
        let setup = try #require(upgraded.sync)
        await signIn(setup, server: firstServer, user: "alice", password: "first password")
        let legacyAccount = try #require(setup.account)
        try await legacyStore.close()

        let app = launch()
        await app.open()
        let legacySync = try #require(app.sync)
        #expect(legacySync.account == legacyAccount)
        #expect(legacySync.serverAddress == firstServer.address)
        await legacySync.sync()
        #expect(legacySync.status == .choosingDirection(.uploadOnly))
        let legacyBackups = try #require(app.backups)
        await legacyBackups.createBackup()
        let originalBackup = try #require(legacyBackups.entries.first)
        let legacyImport = try #require(app.packageImport)
        #expect(legacyImport.backupFolder == backupFolder)
        await app.openPackage(FixturePackage.basicDeck.url)
        guard case .choosingMergeOptions = legacyImport.step else {
            Issue.record("Expected a pending deck package import")
            return
        }

        let profile = try app.addProfile(named: "Second")
        try await app.switchProfile(to: profile.id)
        let second = try #require(app.sync)
        let secondBackups = try #require(app.backups)
        let secondImport = try #require(app.packageImport)
        let newStore = try #require(app.store)
        #expect(second.destination == .ankiWeb)
        #expect(second.account == nil)
        #expect(!second.canRetryMediaSync)
        #expect(secondImport.step == .idle)
        secondBackups.loadBackups()
        #expect(secondBackups.entries.isEmpty)
        await secondBackups.prepareRestore(originalBackup)
        #expect(secondImport.step == .idle)

        await legacySync.upload()
        await legacyImport.startImport()
        #expect(legacySync.status == .idle)
        #expect(legacyImport.step == .idle)
        await signIn(second, server: secondServer, user: "bob", password: "second password")
        let secondAccount = try #require(second.account)
        #expect(secondAccount != legacyAccount)
        try await newStore.addBasicNotes(count: 1, toDeck: newStore.addDeck(named: "Public"))
        await second.sync()
        await second.upload()
        #expect(second.mediaStatus == .synced)
        await secondBackups.createBackup()
        #expect(secondBackups.entries.count == 1)
        try await newStore.close()

        let restarted = launch()
        await restarted.open()
        #expect(restarted.activeProfile.id == profile.id)
        #expect(restarted.sync?.serverAddress == secondServer.address)
        #expect(restarted.sync?.account?.hostKey == secondAccount.hostKey)
        await restarted.sync?.sync()
        #expect(restarted.sync?.status == .synced(SyncOutcome(kind: .merged, serverMessage: nil)))
        try await restarted.switchProfile(to: defaultID)
        #expect(restarted.sync?.account == legacyAccount)
        await restarted.sync?.sync()
        #expect(restarted.sync?.status == .choosingDirection(.uploadOnly), "Only the second server received its collection")
        restarted.backups?.loadBackups()
        #expect(restarted.backups?.entries == [originalBackup])
        let reopened = try #require(restarted.store)
        #expect(try await reopened.deckNames() == ["Default", "Private"])
        try await reopened.close()
    }

    private func signIn(_ model: SyncModel, server: SyncServer, user: String, password: String) async {
        model.selectDestination(.selfHosted)
        model.serverAddress = server.address
        model.userName = user
        model.password = password
        await model.signIn()
    }
}

private final class ProfileTestAccount: SyncAccountStorage {
    private let stored = Mutex<SyncAccount?>(nil)

    func load() throws -> SyncAccount? { stored.withLock { $0 } }
    func save(_ account: SyncAccount) throws { stored.withLock { $0 = account } }
    func remove() throws { stored.withLock { $0 = nil } }
}
