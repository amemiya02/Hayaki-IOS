import AnkiCore
import CollectionStore
import Foundation
import Observation
import PackagesFeature

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
    /// Importing packages into the open collection, once it is ready.
    public private(set) var packageImport: PackageImportModel?
    /// Whether the learner should choose how to start the empty collection.
    public private(set) var showsWelcome = false

    @ObservationIgnored private let location: @Sendable () throws -> CollectionLocation
    @ObservationIgnored private let backupFolder: @Sendable () throws -> URL
    @ObservationIgnored private let language: String
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private var isOpening = false
    private static let welcomeCompletedKey = "hayakiWelcomeCompleted"
    private static let profilesKey = "hayakiProfiles"
    /// A package opened from another app before the collection was ready.
    @ObservationIgnored private var waitingPackage: URL?

    private struct SavedProfiles: Codable {
        var profiles: [CollectionProfile]
        var activeID: UUID
    }

    /// - Parameters:
    ///   - location: Where the original collection lives; the app's standard place unless overridden.
    ///   - backupFolder: Where the original profile's backups go; the app's standard place unless overridden.
    ///   - language: The language for the core's own text, which must be the one the app's screens resolved to.
    ///   - preferences: Where profile and first-run preferences are saved.
    public init(
        location: @escaping @Sendable () throws -> CollectionLocation = { try .standard() },
        backupFolder: @escaping @Sendable () throws -> URL = { try PackageImportModel.standardBackupFolder() },
        language: String = AppModel.screenLanguage,
        preferences: UserDefaults = .standard
    ) {
        self.location = location
        self.backupFolder = backupFolder
        self.language = language
        self.preferences = preferences
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
            let (store, folder) = try await openCollection(for: activeProfile, useFixture: true)
            await showCollection(store, backupFolder: folder)
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
        let profile = CollectionProfile(id: UUID(), name: try validatedName(name))
        try saveProfiles(profiles + [profile], active: activeProfile)
        return profile
    }

    /// Opens the destination in its own core before releasing the current collection.
    public func switchProfile(to id: UUID) async throws {
        guard let target = profiles.first(where: { $0.id == id }) else { throw ProfileError.unavailable }
        guard target != activeProfile else { return }
        guard let previous = store, !isOpening else { throw ProfileError.busy }
        isOpening = true
        state = .opening
        defer { isOpening = false }
        do {
            let (next, folder) = try await openCollection(for: target)
            do {
                try await previous.close()
                try saveProfiles(profiles, active: target)
            } catch {
                try? await next.close()
                throw error
            }
            await showCollection(next, backupFolder: folder)
        } catch {
            state = .ready(previous)
            throw error
        }
    }

    private func openCollection(for profile: CollectionProfile, useFixture: Bool = false) async throws -> (CollectionStore, URL) {
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
        if profile.usesLegacyStorage, useFixture, let package = UITestLaunch.collectionPackage {
            location = try await UITestLaunch.collection(from: package, core: core)
        }
        #endif
        return (try await CollectionStore.open(at: location, core: core), backups)
    }

    private func showCollection(_ store: CollectionStore, backupFolder: URL) async {
        if preferences.bool(forKey: welcomeCompletedKey) {
            showsWelcome = false
        } else {
            // Existing collections with cards or user-created decks skip Welcome.
            let names = try? await store.core.getDeckNames(.with {
                $0.skipEmptyDefault = true
                $0.includeFiltered = true
            })
            showsWelcome = names?.entries.isEmpty == true
            if !showsWelcome, names != nil { completeWelcome() }
        }
        packageImport = PackageImportModel(store: store, backupFolder: backupFolder)
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

    /// Continues to Decks and remembers the choice on the next launch.
    public func completeWelcome() {
        preferences.set(true, forKey: welcomeCompletedKey)
        showsWelcome = false
    }

    private var welcomeCompletedKey: String {
        activeProfile.usesLegacyStorage ? Self.welcomeCompletedKey : "\(Self.welcomeCompletedKey).\(activeProfile.id.uuidString)"
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
