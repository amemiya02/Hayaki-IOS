import AnkiCore
import CollectionStore
import Foundation
import Observation
import PackagesFeature
import SyncFeature

/// Opens the active profile and keeps its collection separate from the other profiles.
@MainActor
@Observable
public final class AppModel {
    public enum State {
        case opening
        case ready(CollectionStore)
        case failed(message: String)
    }

    public private(set) var state: State = .opening
    public private(set) var profiles: [CollectionProfile]
    public private(set) var activeProfile: CollectionProfile
    public private(set) var isSwitchingProfile = false
    public private(set) var sync: SyncModel?
    public private(set) var backups: BackupModel?
    /// Importing packages into the open collection, once it is ready.
    public private(set) var packageImport: PackageImportModel?
    /// Whether the learner should choose how to start the empty collection.
    public private(set) var showsWelcome = false

    @ObservationIgnored private let location: @Sendable () throws -> CollectionLocation
    @ObservationIgnored private let backupFolder: @Sendable () throws -> URL
    @ObservationIgnored private let language: String
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let accountStorage: @Sendable (UUID?) -> any SyncAccountStorage
    @ObservationIgnored private var isOpening = false
    private static let welcomeCompletedKey = "hayakiWelcomeCompleted"
    private static let profilesKey = "hayakiProfiles"
    /// A package opened from another app before the collection was ready.
    @ObservationIgnored private var waitingPackage: URL?
    @ObservationIgnored private var failedCollection: (location: CollectionLocation, backupFolder: URL)?
    #if DEBUG
    @ObservationIgnored private var fixtureLocation: (CollectionLocation, URL)?
    #endif

    public var canRecover: Bool {
        if case .failed = state { return failedCollection != nil }
        return false
    }

    private struct SavedProfiles: Codable {
        var profiles: [CollectionProfile]
        var activeID: UUID
    }

    /// - Parameters:
    ///   - location: Where the original collection lives; the app's standard place unless overridden.
    ///   - backupFolder: Where the original profile's backups go; the app's standard place unless overridden.
    ///   - language: The language for the core's own text, which must be the one the app's screens resolved to.
    ///   - preferences: Where profile and first-run preferences are saved.
    ///   - accountStorage: Where each profile's sign-in is stored, using nil for the original profile.
    public init(
        location: @escaping @Sendable () throws -> CollectionLocation = { try .standard() },
        backupFolder: @escaping @Sendable () throws -> URL = { try PackageImportModel.standardBackupFolder() },
        language: String = AppModel.screenLanguage,
        preferences: UserDefaults = .standard,
        accountStorage: @escaping @Sendable (UUID?) -> any SyncAccountStorage = { KeychainSyncAccountStorage(profileID: $0) }
    ) {
        self.location = location
        self.backupFolder = backupFolder
        self.language = language
        self.preferences = preferences
        self.accountStorage = accountStorage
        let saved = preferences.data(forKey: Self.profilesKey)
            .flatMap { try? PropertyListDecoder().decode(SavedProfiles.self, from: $0) }
        if let saved, let active = saved.profiles.first(where: { $0.id == saved.activeID }) {
            profiles = saved.profiles
            activeProfile = active
        } else {
            profiles = [.legacy]
            activeProfile = .legacy
        }
    }

    /// The open collection, once it is ready.
    public var store: CollectionStore? {
        if case .ready(let store) = state { store } else { nil }
    }

    /// Opens the collection unless it is already open or opening has failed.
    public func open() async {
        guard case .opening = state, !isOpening else { return }
        isOpening = true
        defer { isOpening = false }
        do {
            let (store, folder) = try await openCollection(for: activeProfile, recordRecovery: true)
            let welcome = await shouldShowWelcome(for: activeProfile, in: store)
            showCollection(store, backupFolder: folder, welcome: welcome)
            if let waiting = waitingPackage {
                waitingPackage = nil
                await packageImport?.open(waiting)
            }
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    /// Adds an empty profile, leaving the current collection open.
    @discardableResult
    public func addProfile(named name: String) throws -> CollectionProfile {
        guard !isSwitchingProfile else { throw ProfileError.busy }
        let profile = CollectionProfile(id: UUID(), name: try validatedName(name))
        try saveProfiles(profiles + [profile], active: activeProfile)
        return profile
    }

    /// Opens the destination in its own core before releasing the current collection.
    public func switchProfile(to id: UUID) async throws {
        guard let target = profiles.first(where: { $0.id == id }) else { throw ProfileError.unavailable }
        guard target != activeProfile else { return }
        guard let previous = store, !isOpening, !isSwitchingProfile,
              sync?.isBusy == false, packageImport?.isBusy == false, backups?.isBusy == false
        else { throw ProfileError.busy }
        let saved = try PropertyListEncoder().encode(SavedProfiles(profiles: profiles, activeID: id))

        isSwitchingProfile = true
        previous.allowsNewProfileWork = false
        defer {
            isSwitchingProfile = false
            if activeProfile.id != id { previous.allowsNewProfileWork = true }
        }

        let (next, folder) = try await openCollection(for: target)
        let welcome = await shouldShowWelcome(for: target, in: next)
        do {
            try await previous.close()
        } catch {
            try? await next.close()
            throw error
        }
        sync?.keepBoth()
        packageImport?.cancel()
        preferences.set(saved, forKey: Self.profilesKey)
        activeProfile = target
        showCollection(next, backupFolder: folder, welcome: welcome)
    }

    private func openCollection(for profile: CollectionProfile, recordRecovery: Bool = false) async throws -> (CollectionStore, URL) {
        var location = try location()
        var backups = try backupFolder()
        if !profile.usesLegacyStorage {
            let directory = profile.id.uuidString
            location = CollectionLocation(folder: location.folder.deletingLastPathComponent()
                .appendingPathComponent("Profiles", isDirectory: true)
                .appendingPathComponent(directory, isDirectory: true)
                .appendingPathComponent("Collection", isDirectory: true))
            backups.appendPathComponent(directory, isDirectory: true)
        }
        let core = try await CoreClient(language: language)
        #if DEBUG
        if profile.usesLegacyStorage, let package = UITestLaunch.collectionPackage {
            if let fixtureLocation {
                (location, backups) = fixtureLocation
            } else {
                location = try await UITestLaunch.collection(from: package, core: core)
                backups = location.folder.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
                fixtureLocation = (location, backups)
            }
        }
        #endif
        if recordRecovery { failedCollection = (location, backups) }
        let store = try await CollectionStore.open(at: location, core: core)
        if recordRecovery { failedCollection = nil }
        return (store, backups)
    }

    private func shouldShowWelcome(for profile: CollectionProfile, in store: CollectionStore) async -> Bool {
        let key = welcomeCompletedKey(for: profile)
        guard !preferences.bool(forKey: key) else { return false }
        // Existing collections with cards or user-created decks skip Welcome.
        let names = try? await store.core.getDeckNames(.with {
            $0.skipEmptyDefault = true
            $0.includeFiltered = true
        })
        if names?.entries.isEmpty == false { preferences.set(true, forKey: key) }
        return names?.entries.isEmpty == true
    }

    private func showCollection(_ store: CollectionStore, backupFolder: URL, welcome: Bool) {
        let importer = PackageImportModel(store: store, backupFolder: backupFolder)
        let profileID = activeProfile.usesLegacyStorage ? nil : activeProfile.id
        sync = SyncModel(store: store, storage: accountStorage(profileID))
        backups = BackupModel(store: store, folder: backupFolder, importer: importer)
        packageImport = importer
        showsWelcome = welcome
        state = .ready(store)
    }

    private func validatedName(_ name: String) throws -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw ProfileError.emptyName }
        guard cleaned.utf16.count <= 50 else { throw ProfileError.nameTooLong }
        guard !profiles.contains(where: { $0.name.caseInsensitiveCompare(cleaned) == .orderedSame }) else {
            throw ProfileError.duplicateName
        }
        return cleaned
    }

    private func saveProfiles(_ profiles: [CollectionProfile], active: CollectionProfile) throws {
        let sorted = profiles.sorted { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending }
        let saved = SavedProfiles(profiles: sorted, activeID: active.id)
        preferences.set(try PropertyListEncoder().encode(saved), forKey: Self.profilesKey)
        self.profiles = sorted
        activeProfile = active
    }

    /// Restores a selected backup when the active profile's database could not open.
    public func recoverCollection(from package: URL) async {
        guard canRecover, let failedCollection, !isOpening else { return }
        isOpening = true
        state = .opening
        do {
            let core = try await CoreClient(language: language)
            try await PackageImportModel.restoreAfterFailedOpen(
                from: package, core: core, location: failedCollection.location, backupFolder: failedCollection.backupFolder
            )
            isOpening = false
            await open()
        } catch {
            isOpening = false
            state = .failed(message: error.localizedDescription)
        }
    }

    /// Continues to Decks and remembers the choice on the next launch.
    public func completeWelcome() {
        preferences.set(true, forKey: welcomeCompletedKey(for: activeProfile))
        showsWelcome = false
    }

    private func welcomeCompletedKey(for profile: CollectionProfile) -> String {
        profile.usesLegacyStorage ? Self.welcomeCompletedKey : "\(Self.welcomeCompletedKey).\(profile.id.uuidString)"
    }

    /// Starts importing a package opened in another app or queues it during launch.
    public func openPackage(_ url: URL) async {
        if let packageImport {
            await packageImport.open(url)
        } else {
            waitingPackage = url
        }
    }

    /// The language the app's own screens are shown in.
    public nonisolated static var screenLanguage: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }
}
