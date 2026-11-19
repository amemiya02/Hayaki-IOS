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
    @Test("Deleting an inactive profile removes its files and sign-in and preserves the active profile")
    func deleteInactiveProfile() async throws {
        let folder = try TemporaryFolder()
        let location = CollectionLocation(folder: folder.url.appendingPathComponent("Collection"))
        let backups = folder.url.appendingPathComponent("Backups")
        let suite = "HayakiProfilesTests.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let legacyAccount = ProfileTestAccount()
        let otherAccount = ProfileTestAccount()
        func launch() -> AppModel {
            AppModel(location: { location }, backupFolder: { backups }, language: "en", preferences: preferences,
                     accountStorage: { profileID in profileID == nil ? legacyAccount : otherAccount })
        }

        let app = launch()
        await app.open()
        let legacy = app.activeProfile
        await #expect(throws: ProfileError.lastProfile) { try await app.deleteProfile(legacy.id) }
        let other = try app.addProfile(named: "Second")
        await #expect(throws: ProfileError.activeProfile) { try await app.deleteProfile(legacy.id) }

        let oldStore = try #require(app.store)
        let removedDeck = try await oldStore.addDeck(named: "Old")
        try await oldStore.addBasicNotes(count: 1, toDeck: removedDeck)
        try await oldStore.addMediaFile(named: "old.png", data: Data([0]))
        await app.backups?.createBackup()
        try await app.switchProfile(to: other.id)
        let current = try #require(app.store)
        try await current.addDeck(named: "Kept")
        try await current.addMediaFile(named: "kept.png", data: Data([1]))
        let activeBackups = try #require(app.backups)
        try await current.addBasicNotes(count: 1, toDeck: current.addDeck(named: "Backup"))
        await activeBackups.createBackup()
        #expect(activeBackups.entries.count == 1)
        try legacyAccount.save(SyncAccount(server: nil, userName: "old", hostKey: "old-key"))
        try otherAccount.save(SyncAccount(server: nil, userName: "kept", hostKey: "kept-key"))

        try await app.deleteProfile(legacy.id)

        #expect(app.profiles == [other])
        #expect(try legacyAccount.load() == nil)
        #expect(try otherAccount.load()?.hostKey == "kept-key")
        #expect(!FileManager.default.fileExists(atPath: location.folder.path))
        #expect(!FileManager.default.fileExists(atPath: backups.path))
        #expect(try current.mediaFileNames().contains("kept.png"))
        try await current.close()

        let reopened = launch()
        await reopened.open()
        #expect(reopened.profiles == [other])
        #expect(reopened.activeProfile == other)
        #expect(try await reopened.store?.deckNames().contains("Kept") == true)
        reopened.backups?.loadBackups()
        #expect(reopened.backups?.entries.count == 1)
        try await reopened.store?.close()
    }

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

    @Test("Sync preferences reopen with their profile")
    func syncPreferencesReopenSeparately() async throws {
        let folder = try TemporaryFolder()
        let location = CollectionLocation(folder: folder.url.appendingPathComponent("Collection"))
        let backups = folder.url.appendingPathComponent("Backups")
        let suiteName = "HayakiProfilesTests.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }

        func launch() -> AppModel {
            AppModel(
                location: { location }, backupFolder: { backups }, language: "en",
                preferences: preferences, accountStorage: { _ in ProfileTestAccount() }
            )
        }

        let app = launch()
        await app.open()
        let originalID = app.activeProfile.id
        let original = try #require(app.sync)
        #expect(original.policy == SyncPolicy())
        original.policy.automatic = true
        original.policy.allowsMetered = true
        original.policy.showsStatusBadge = false
        original.policy.media = .onlyUnmetered
        let validTimeout = original.policy.setTimeoutSeconds(75)
        let tooShort = original.policy.setTimeoutSeconds(29)
        let tooLong = original.policy.setTimeoutSeconds(100_000)
        #expect(validTimeout)
        #expect(!tooShort)
        #expect(!tooLong)
        let firstPolicy = original.policy

        let secondID = try app.addProfile(named: "Second").id
        try await app.switchProfile(to: secondID)
        let second = try #require(app.sync)
        #expect(second.policy == SyncPolicy())
        second.policy.media = .never
        try await app.store?.close()

        let restarted = launch()
        await restarted.open()
        #expect(restarted.activeProfile.id == secondID)
        #expect(restarted.sync?.policy.media == .never)
        #expect(restarted.sync?.policy.timeoutSeconds == 60)
        try await restarted.switchProfile(to: originalID)
        #expect(restarted.sync?.policy == firstPolicy)
        try await restarted.store?.close()
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

    @Test("Renaming a profile preserves its identity and rejects duplicate names")
    func renameProfile() async throws {
        let folder = try TemporaryFolder()
        let location = CollectionLocation(folder: folder.url.appendingPathComponent("Collection"))
        let backups = folder.url.appendingPathComponent("Backups")
        let suite = "HayakiProfilesTests.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }

        func launch() -> AppModel {
            AppModel(location: { location }, backupFolder: { backups }, language: "en", preferences: preferences)
        }

        let app = launch()
        await app.open()
        let profile = try app.addProfile(named: "German")
        try await app.switchProfile(to: profile.id)
        let store = try #require(app.store)
        let profilePath = store.location
        try await store.addDeck(named: "Grammar")

        #expect(throws: ProfileError.duplicateName) { try app.renameProfile(profile.id, to: " default ") }
        #expect(throws: ProfileError.emptyName) { try app.renameProfile(profile.id, to: " ") }
        #expect(throws: ProfileError.nameTooLong) {
            try app.renameProfile(profile.id, to: String(repeating: "a", count: 51))
        }
        try app.renameProfile(profile.id, to: "german")
        try app.renameProfile(profile.id, to: "  Deutsch   B2 ")
        #expect(app.activeProfile.id == profile.id)
        #expect(app.activeProfile.name == "Deutsch   B2")
        try await store.close()

        let restarted = launch()
        await restarted.open()
        #expect(restarted.activeProfile.name == "Deutsch   B2")
        let reopened = try #require(restarted.store)
        #expect(reopened.location == profilePath)
        #expect(try await reopened.deckNames() == ["Default", "Grammar"])
        try await reopened.close()
    }

    @Test("A collection package export keeps the current profile open through its reopen")
    func switchWaitsForCollectionExport() async throws {
        let folder = try TemporaryFolder()
        let location = CollectionLocation(folder: folder.url.appendingPathComponent("Collection"))
        let backups = folder.url.appendingPathComponent("Backups")
        let exports = folder.url.appendingPathComponent("Exports")
        let suite = "HayakiProfilesTests.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let app = AppModel(location: { location }, backupFolder: { backups }, language: "en", preferences: preferences)
        await app.open()
        let original = app.activeProfile
        let current = try #require(app.store)
        let next = try app.addProfile(named: "Next")
        let exporter = PackageExportModel(store: current, exportFolder: exports)

        let export = Task { await exporter.export() }
        while exporter.step == .choosing { await Task.yield() }
        try #require(exporter.isExporting)
        await #expect(throws: ProfileError.busy) { try await app.switchProfile(to: next.id) }
        await export.value

        guard case .finished = exporter.step else {
            Issue.record("Expected the current collection to finish exporting, got \(exporter.step)")
            return
        }
        #expect(app.activeProfile == original)
        try await app.switchProfile(to: next.id)
        #expect(!exporter.canExport)
        #expect(app.activeProfile == next)
        #expect(try await app.store?.deckNames() == ["Default"])
        try await app.store?.close()
    }

    @Test("An active sync blocks switching until the core stops")
    func switchWaitsForActiveSync() async throws {
        let folder = try TemporaryFolder()
        let location = CollectionLocation(folder: folder.url.appendingPathComponent("Collection"))
        let backups = folder.url.appendingPathComponent("Backups")
        let suite = "HayakiProfilesTests.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let storage = ProfileTestAccount()
        let server = try ListeningSocket()
        let app = AppModel(
            location: { location }, backupFolder: { backups }, language: "en",
            preferences: preferences, accountStorage: { _ in storage }
        )
        await app.open()
        let original = app.activeProfile
        let second = try app.addProfile(named: "Second")
        let sync = try #require(app.sync)
        sync.selectDestination(.selfHosted)
        sync.serverAddress = server.address
        sync.userName = "alice"
        sync.password = "passphrase"

        let signingIn = Task { await sync.signIn() }
        defer { signingIn.cancel() }
        try await eventually("the core to contact the server") { sync.isBusy }
        await #expect(throws: ProfileError.busy) { try await app.switchProfile(to: second.id) }
        #expect(app.activeProfile == original)
        try await Task.sleep(for: .milliseconds(500))
        sync.cancel()
        await signingIn.value
        #expect(sync.status.failure?.reason == .cancelled)

        try await app.switchProfile(to: second.id)
        #expect(app.activeProfile == second)
        #expect(app.sync?.destination == .ankiWeb)
        try await app.store?.close()
    }

    @Test("A new profile's backup does not postpone the original profile's automatic backup")
    func automaticBackupIsIndependent() async throws {
        let folder = try TemporaryFolder()
        let location = CollectionLocation(folder: folder.url.appendingPathComponent("Collection"))
        let backups = folder.url.appendingPathComponent("Backups")
        let suite = "HayakiProfilesTests.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }

        let app = AppModel(location: { location }, backupFolder: { backups }, language: "en", preferences: preferences)
        await app.open()
        let original = app.activeProfile
        let firstStore = try #require(app.store)
        try await firstStore.addBasicNotes(count: 1, toDeck: firstStore.addDeck(named: "First"))

        let second = try app.addProfile(named: "Second")
        try await app.switchProfile(to: second.id)
        let secondStore = try #require(app.store)
        try await secondStore.addBasicNotes(count: 1, toDeck: secondStore.addDeck(named: "Second"))
        let secondBackups = try #require(app.backups)
        await secondBackups.createBackup()
        #expect(secondBackups.entries.count == 1)

        try await app.switchProfile(to: original.id)
        let firstBackups = try #require(app.backups)
        await firstBackups.createAutomaticBackup()
        #expect(firstBackups.entries.count == 1)
        try await app.store?.close()
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
