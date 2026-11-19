import AnkiCore
import CollectionStore
import DecksFeature
import ExtensionBridge
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
    public var isSwitchingProfile: Bool { switchDestination != nil }
    private var switchDestination: UUID?
    public private(set) var sync: SyncModel?
    public private(set) var backups: BackupModel?
    /// Importing packages into the open collection, once it is ready.
    public private(set) var packageImport: PackageImportModel?
    public private(set) var textImport: TextImportModel?
    /// Whether the learner should choose how to start the empty collection.
    public private(set) var showsWelcome = false

    struct LinkRequest: Identifiable, Equatable {
        let id = UUID()
        let link: DeckLink
    }

    let appExtensions: AppExtensions?
    var waitingDeckLink: LinkRequest?
    var decksRequested: UUID?
    var deckPresentation: DeckPresentation?
    var deckLinkError: String?
    var packageLinkError: String?
    @ObservationIgnored private var isRouting = false

    var collectionIsIdle: Bool {
        store?.isExportingPackage == false && !isSwitchingProfile && sync?.isBusy == false
            && packageImport?.isBusy == false && textImport?.isWorking == false && backups?.isBusy == false
    }

    var canHandleExtensionWork: Bool {
        collectionIsIdle && appExtensions?.isConsuming != true && appExtensions?.editorDraft == nil
    }

    @ObservationIgnored private let location: @Sendable () throws -> CollectionLocation
    @ObservationIgnored private let backupFolder: @Sendable () throws -> URL
    @ObservationIgnored private let language: String
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let accountStorage: @Sendable (UUID?) -> any SyncAccountStorage
    @ObservationIgnored private var isOpening = false
    private static let welcomeCompletedKey = "hayakiWelcomeCompleted"
    private static let profilesKey = "hayakiProfiles"
    private struct ImportRequest {
        let profileID: UUID
        let file: ImportURL
    }

    /// Keeps a Files provider's resource accessible until its importer has staged a copy.
    private final class ImportURL {
        let url: URL
        private let isSecurityScoped: Bool

        init(_ url: URL) {
            self.url = url
            isSecurityScoped = url.startAccessingSecurityScopedResource()
        }

        deinit {
            if isSecurityScoped { url.stopAccessingSecurityScopedResource() }
        }
    }

    private var waitingImports: [ImportRequest] = []

    var canRouteWaitingImport: Bool {
        collectionIsIdle && packageImport?.step == .idle && textImport?.isPresented == false
            && waitingImports.contains { $0.profileID == activeProfile.id }
    }
    @ObservationIgnored private var failedCollection: (location: CollectionLocation, backupFolder: URL)?
    #if DEBUG
    @ObservationIgnored private var loadedFixture = false
    #endif

    public var canRecover: Bool {
        if case .failed = state { return failedCollection != nil }
        return false
    }

    private struct SavedProfiles: Codable {
        var profiles: [CollectionProfile]
        var activeID: UUID
        var pendingDeletions: Set<UUID>?
    }

    @ObservationIgnored private var pendingProfileDeletions: Set<UUID> = []
    @ObservationIgnored private var deletingProfiles: Set<UUID> = []

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
        accountStorage: @escaping @Sendable (UUID?) -> any SyncAccountStorage = { KeychainSyncAccountStorage(profileID: $0) },
        extensionBridge: ExtensionBridge? = nil
    ) {
        self.location = location
        self.backupFolder = backupFolder
        self.language = language
        self.preferences = preferences
        self.accountStorage = accountStorage
        appExtensions = extensionBridge.map(AppExtensions.init)
        let saved = preferences.data(forKey: Self.profilesKey)
            .flatMap { try? PropertyListDecoder().decode(SavedProfiles.self, from: $0) }
        if let saved, let active = saved.profiles.first(where: { $0.id == saved.activeID }) {
            profiles = saved.profiles
            activeProfile = active
            pendingProfileDeletions = (saved.pendingDeletions ?? []).subtracting(saved.profiles.map(\.id))
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
            await routeWaitingImport()
            for id in pendingProfileDeletions {
                try? await finishDeletingProfile(id)
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

    /// Changes the display name while keeping the profile's data and sign-in in place.
    public func renameProfile(_ id: UUID, to name: String) throws {
        guard !isSwitchingProfile else { throw ProfileError.busy }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw ProfileError.unavailable }
        let renamed = CollectionProfile(id: id, name: try validatedName(name, ignoring: id))
        var updated = profiles
        updated[index] = renamed
        try saveProfiles(updated, active: activeProfile.id == id ? renamed : activeProfile)
    }

    /// Permanently removes an inactive profile and its collection, media, backups and sign-in.
    public func deleteProfile(_ id: UUID) async throws {
        guard !isSwitchingProfile else { throw ProfileError.busy }
        guard profiles.contains(where: { $0.id == id }) else { throw ProfileError.unavailable }
        guard profiles.count > 1 else { throw ProfileError.lastProfile }
        guard id != activeProfile.id else { throw ProfileError.activeProfile }
        let paths = try profilePaths(for: id)
        // Commit the removal and its cleanup record together before deleting any files.
        try saveProfiles(profiles.filter { $0.id != id }, active: activeProfile,
                         pendingDeletions: pendingProfileDeletions.union([id]))
        waitingImports.removeAll { $0.profileID == id }
        try await finishDeletingProfile(id, paths: paths)
    }

    private func finishDeletingProfile(_ id: UUID, paths: ProfilePaths? = nil) async throws {
        guard pendingProfileDeletions.contains(id), deletingProfiles.insert(id).inserted else { return }
        defer { deletingProfiles.remove(id) }
        let paths = try paths ?? profilePaths(for: id)
        let storage = accountStorage(id == CollectionProfile.legacyID ? nil : id)
        try await Task.detached(priority: .utility) {
            for folder in [paths.profileFolder, paths.backups] {
                do {
                    try FileManager.default.removeItem(at: folder)
                } catch let error as CocoaError where error.code == .fileNoSuchFile {
                    // The profile may be unopened, or an earlier attempt already cleaned this folder.
                }
            }
            try storage.remove()
        }.value
        preferences.removeObject(forKey: welcomeCompletedKey(for: id))
        try saveProfiles(profiles, active: activeProfile, pendingDeletions: pendingProfileDeletions.subtracting([id]))
    }

    /// Opens the destination in its own core before releasing the current collection.
    public func switchProfile(to id: UUID) async throws {
        guard let target = profiles.first(where: { $0.id == id }) else { throw ProfileError.unavailable }
        guard target != activeProfile else { return }
        guard let previous = store, !isOpening, deletingProfiles.isEmpty, canHandleExtensionWork else {
            throw ProfileError.busy
        }
        let saved = try PropertyListEncoder().encode(SavedProfiles(
            profiles: profiles, activeID: id, pendingDeletions: pendingProfileDeletions
        ))

        switchDestination = id
        previous.allowsNewProfileWork = false

        let next: CollectionStore
        let folder: URL
        let welcome: Bool
        do {
            (next, folder) = try await openCollection(for: target)
            welcome = await shouldShowWelcome(for: target, in: next)
            do {
                try await previous.close()
            } catch {
                try? await next.close()
                throw error
            }
        } catch {
            previous.allowsNewProfileWork = true
            switchDestination = nil
            if waitingImports.contains(where: { $0.profileID == id }) {
                waitingImports.removeAll { $0.profileID == id }
                packageLinkError = String(localized: "The import was cancelled because “\(target.name)” could not open.",
                                          bundle: .module)
            }
            throw error
        }
        sync?.cancelDestinationChange()
        sync?.keepBoth()
        sync?.password = ""
        packageImport?.cancel()
        textImport?.dismiss()
        preferences.set(saved, forKey: Self.profilesKey)
        appExtensions?.clearSnapshot()
        decksRequested = nil
        deckPresentation = nil
        activeProfile = target
        showCollection(next, backupFolder: folder, welcome: welcome)
        switchDestination = nil
        await routeWaitingImport()
    }

    private struct ProfilePaths: Sendable {
        let profileFolder: URL
        let location: CollectionLocation
        let backups: URL
    }

    private func profilePaths(for id: UUID) throws -> ProfilePaths {
        let originalLocation = try location()
        let originalBackups = try backupFolder()
        if id == CollectionProfile.legacyID {
            return ProfilePaths(profileFolder: originalLocation.folder, location: originalLocation, backups: originalBackups)
        }
        let directory = id.uuidString
        let profileFolder = originalLocation.folder.deletingLastPathComponent()
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(directory, isDirectory: true)
        let profileLocation = CollectionLocation(folder: profileFolder.appendingPathComponent("Collection", isDirectory: true))
        // Anki's automatic backup interval looks at the age of every
        // directory entry. Keep the profile directories outside Backups.
        let backups = originalBackups.deletingLastPathComponent()
            .appendingPathComponent("Profile Backups", isDirectory: true)
            .appendingPathComponent(directory, isDirectory: true)
        return ProfilePaths(profileFolder: profileFolder, location: profileLocation, backups: backups)
    }

    private func openCollection(for profile: CollectionProfile, recordRecovery: Bool = false) async throws -> (CollectionStore, URL) {
        let paths = try profilePaths(for: profile.id)
        let location = paths.location
        let backups = paths.backups
        let core = try await CoreClient(language: language)
        #if DEBUG
        if profile.usesLegacyStorage, !loadedFixture, let package = UITestLaunch.collectionPackage {
            try await UITestLaunch.seedCollection(at: location, from: package, core: core)
            loadedFixture = true
        }
        #endif
        if recordRecovery { failedCollection = (location, backups) }
        let store = try await CollectionStore.open(at: location, core: core)
        if recordRecovery { failedCollection = nil }
        return (store, backups)
    }

    private func shouldShowWelcome(for profile: CollectionProfile, in store: CollectionStore) async -> Bool {
        let key = welcomeCompletedKey(for: profile.id)
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
        textImport = TextImportModel(store: store)
        showsWelcome = welcome
        state = .ready(store)
    }

    func routeWaitingDeckLink() async {
        guard !isRouting else { return }
        isRouting = true
        defer { isRouting = false }

        while canHandleExtensionWork, !isOpening, let request = waitingDeckLink {
            do {
                if let profileID = request.link.profileID, profileID != activeProfile.id {
                    try await switchProfile(to: profileID)
                }
                guard request == waitingDeckLink else { continue }
                completeWelcome()
                if case .deck(_, let id, let action) = request.link {
                    deckPresentation = DeckPresentation(deckID: id, showsOptions: action == .options)
                } else {
                    deckPresentation = nil
                }
                decksRequested = request.id
            } catch {
                guard request == waitingDeckLink else { continue }
                deckLinkError = error.localizedDescription
            }
            waitingDeckLink = nil
        }
    }

    private func validatedName(_ name: String, ignoring id: UUID? = nil) throws -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw ProfileError.emptyName }
        guard cleaned.utf16.count <= 50 else { throw ProfileError.nameTooLong }
        guard !profiles.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(cleaned) == .orderedSame }) else {
            throw ProfileError.duplicateName
        }
        return cleaned
    }

    private func saveProfiles(
        _ profiles: [CollectionProfile],
        active: CollectionProfile,
        pendingDeletions: Set<UUID>? = nil
    ) throws {
        let sorted = profiles.sorted { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending }
        let pending = pendingDeletions ?? pendingProfileDeletions
        let saved = SavedProfiles(profiles: sorted, activeID: active.id, pendingDeletions: pending.isEmpty ? nil : pending)
        preferences.set(try PropertyListEncoder().encode(saved), forKey: Self.profilesKey)
        self.profiles = sorted
        activeProfile = active
        pendingProfileDeletions = pending
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
        preferences.set(true, forKey: welcomeCompletedKey(for: activeProfile.id))
        showsWelcome = false
    }

    private func welcomeCompletedKey(for id: UUID) -> String {
        id == CollectionProfile.legacyID ? Self.welcomeCompletedKey : "\(Self.welcomeCompletedKey).\(id.uuidString)"
    }

    /// Routes an import file into the profile being opened, or the active profile.
    public func openPackage(_ url: URL) async {
        waitingImports.append(ImportRequest(profileID: switchDestination ?? activeProfile.id, file: ImportURL(url)))
        await routeWaitingImport()
    }

    func routeWaitingImport() async {
        guard canRouteWaitingImport, let packageImport, let textImport,
              let index = waitingImports.firstIndex(where: { $0.profileID == activeProfile.id }) else { return }
        let request = waitingImports.remove(at: index)
        let url = request.file.url
        switch url.pathExtension.lowercased() {
        case "csv", "tsv", "txt":
            await textImport.prepare(url)
        default:
            await packageImport.open(url)
        }
        // The provider may revoke access as soon as the request is released.
        withExtendedLifetime(request) {}
    }

    /// The language the app's own screens are shown in.
    public nonisolated static var screenLanguage: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }
}
