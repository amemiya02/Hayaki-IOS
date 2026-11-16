import AnkiCore
import CollectionStore
import Foundation
import Observation
import PackagesFeature

/// The app at launch: starts the core and opens the learner's collection, in
/// the background, creating an empty collection the first time.
@MainActor
@Observable
public final class AppModel {
    public enum State {
        case opening
        case ready(CollectionStore)
        case failed(message: String)
    }

    public private(set) var state: State = .opening
    /// Importing packages into the open collection, once it is ready.
    public private(set) var packageImport: PackageImportModel?

    @ObservationIgnored private let location: @Sendable () throws -> CollectionLocation
    @ObservationIgnored private let backupFolder: @Sendable () throws -> URL
    @ObservationIgnored private let language: String
    /// A package opened from another app before the collection was ready.
    @ObservationIgnored private var waitingPackage: URL?

    /// - Parameters:
    ///   - location: Where the collection lives; the app's standard place
    ///     unless a test passes another.
    ///   - backupFolder: Where backups go; the app's standard place unless a
    ///     test passes another.
    ///   - language: The language for the core's own text, which must be the
    ///     one the app's screens resolved to.
    public init(
        location: @escaping @Sendable () throws -> CollectionLocation = { try .standard() },
        backupFolder: @escaping @Sendable () throws -> URL = { try PackageImportModel.standardBackupFolder() },
        language: String = AppModel.screenLanguage
    ) {
        self.location = location
        self.backupFolder = backupFolder
        self.language = language
    }

    /// The open collection, once it is ready.
    public var store: CollectionStore? {
        if case .ready(let store) = state { store } else { nil }
    }

    /// Opens the collection unless it is already open or opening has failed.
    /// The core does the work on its own thread, so the interface stays
    /// responsive meanwhile.
    public func open() async {
        guard case .opening = state else { return }
        do {
            let core = try await CoreClient(language: language)
            let store = try await CollectionStore.open(at: try location(), core: core)
            let packageImport = PackageImportModel(store: store, backupFolder: try backupFolder())
            self.packageImport = packageImport
            state = .ready(store)
            if let waiting = waitingPackage {
                waitingPackage = nil
                await packageImport.open(waiting)
            }
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    /// Starts importing a package the learner opened from Files, AirDrop or
    /// another app's share sheet. One opened while the app is still launching
    /// is taken in as soon as the collection is open.
    public func openPackage(_ url: URL) async {
        if let packageImport {
            await packageImport.open(url)
        } else {
            waitingPackage = url
        }
    }

    /// The language the app's own screens are shown in: the first of the
    /// learner's preferred languages that the app has strings for.
    public nonisolated static var screenLanguage: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }
}
