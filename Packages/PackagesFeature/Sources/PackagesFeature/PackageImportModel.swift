import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Observation

/// Importing a package, from the moment the learner chooses or opens one to
/// the summary of what the import did.
///
/// A collection package replaces the collection: the learner is warned and
/// must confirm, and a backup of the current collection is made first. A deck
/// package is merged into the collection with the choices in `mergeOptions`.
/// Both go through the core's own import, which shows progress and can be
/// cancelled; a cancelled or failed import leaves the collection as it was.
@MainActor
@Observable
public final class PackageImportModel {
    public enum Step: Equatable {
        /// No import under way.
        case idle
        /// Copying the chosen file so it can be read.
        case preparing(name: String)
        /// A collection package waits for the learner to confirm replacing
        /// the collection.
        case confirmingReplace(PackageFile)
        /// A deck package waits for the learner's merge choices.
        case choosingMergeOptions(PackageFile)
        /// The core is importing; `progress` is its own description of the
        /// current stage, once it has reported one.
        case importing(PackageFile, progress: String?)
        case finished(ImportSummary)
        /// The learner cancelled the import; the collection is unchanged.
        case cancelled
        case failed(message: String)
    }

    public private(set) var step: Step = .idle
    /// The learner's choices for merging a deck package. Opening one fills
    /// them with the choices the collection remembers from the last import.
    public var mergeOptions = MergeOptions()

    @ObservationIgnored private let store: CollectionStore
    public let backupFolder: URL
    @ObservationIgnored private var cancelRunningOperation: (() -> Void)?
    @ObservationIgnored private var cancelRequested = false

    /// - Parameters:
    ///   - backupFolder: Where the backup made before a collection package
    ///     replaces the collection goes.
    public init(store: CollectionStore, backupFolder: URL) {
        self.store = store
        self.backupFolder = backupFolder
    }

    /// The folder backups go to: `Backups` in the app's Documents folder,
    /// which the Files app shows.
    public nonisolated static func standardBackupFolder(fileManager: FileManager = .default) throws -> URL {
        try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Backups", isDirectory: true)
    }

    /// Whether the core is importing now, so another package cannot start.
    public var isImporting: Bool {
        if case .importing = step { true } else { false }
    }

    /// Takes in a package the learner chose or opened from another app, and
    /// asks for confirmation (collection package) or merge choices (deck
    /// package). Nothing in the collection changes yet. Ignored while an
    /// import is running.
    public func open(_ url: URL) async {
        guard !isImporting else { return }
        discardPendingPackage()
        step = .preparing(name: url.lastPathComponent)
        do {
            let package = try await PackageFile.stage(url)
            // The learner may have cancelled while the file was copied.
            guard case .preparing = step else {
                package.discard()
                return
            }
            switch package.kind {
            case .collectionPackage:
                step = .confirmingReplace(package)
            case .deckPackage:
                mergeOptions = MergeOptions(try await store.core.getImportAnkiPackagePresets())
                step = .choosingMergeOptions(package)
            }
        } catch is NotAPackage {
            step = .failed(message: String(
                localized: "Hayaki can import Anki collection packages (.colpkg) and deck packages (.apkg).",
                bundle: .module,
                comment: "Shown when the learner opens a file that is not an Anki package."
            ))
        } catch {
            step = .failed(message: error.localizedDescription)
        }
    }

    /// Imports the package waiting for confirmation or merge choices.
    public func startImport() async {
        let package: PackageFile
        switch step {
        case .confirmingReplace(let waiting), .choosingMergeOptions(let waiting):
            package = waiting
        default:
            return
        }
        cancelRequested = false
        step = .importing(package, progress: nil)
        defer {
            cancelRunningOperation = nil
            package.discard()
        }
        do {
            let summary = switch package.kind {
            case .collectionPackage: try await replaceCollection(with: package)
            case .deckPackage: try await merge(package)
            }
            step = .finished(summary)
        } catch let error as CoreError where error.isInterrupted {
            step = .cancelled
        } catch {
            step = .failed(message: error.localizedDescription)
        }
    }

    /// Stops a running import, or puts away a package waiting for the
    /// learner's go-ahead.
    public func cancel() {
        switch step {
        case .importing:
            cancelRequested = true
            cancelRunningOperation?()
        case .preparing, .confirmingReplace, .choosingMergeOptions:
            discardPendingPackage()
            step = .idle
        case .idle, .finished, .cancelled, .failed:
            step = .idle
        }
    }

    /// Closes the summary or the message about a cancelled or failed import.
    public func dismiss() {
        guard !isImporting else { return }
        cancel()
    }

    // MARK: Importing

    private func merge(_ package: PackageFile) async throws -> ImportSummary {
        let operation = store.core.start(.importAnkiPackage(.with {
            $0.packagePath = package.url.path
            $0.options = mergeOptions.request
        }))
        follow(operation, importing: package)
        let response = try await store.modify(operation)
        return .merged(MergeResult(response.log))
    }

    private func replaceCollection(with package: PackageFile) async throws -> ImportSummary {
        let backupMade = try await store.backUp(to: backupFolder, force: true)
        try throwIfCancelled()
        try await store.replace { core, location in
            let operation = core.start(.importCollectionPackage(location.importRequest(from: package)))
            follow(operation, importing: package)
            _ = try await operation.result
        }
        return .replaced(ReplaceResult(
            decks: try await store.core.getDeckNames(.with {
                $0.skipEmptyDefault = true
                $0.includeFiltered = true
            }).entries.count,
            notes: try await store.core.searchNotes(.with { $0.search = "" }).ids.count,
            cards: try await store.core.searchCards(.with { $0.search = "" }).ids.count,
            backupMade: backupMade
        ))
    }

    /// Lets the learner cancel `operation` and shows its progress until it
    /// ends.
    private func follow<Response>(_ operation: LongOperation<Response>, importing package: PackageFile) {
        cancelRunningOperation = { operation.cancel() }
        if cancelRequested { operation.cancel() }
        Task { [weak self] in
            for await progress in operation.progress {
                guard case .importing(let text)? = progress.value else { continue }
                guard let self, case .importing(let current, _) = self.step, current == package else { return }
                self.step = .importing(package, progress: text)
            }
        }
    }

    private func throwIfCancelled() throws(CoreError) {
        if cancelRequested { throw CoreError(kind: .interrupted, message: "Interrupted") }
    }

    private func discardPendingPackage() {
        switch step {
        case .confirmingReplace(let package), .choosingMergeOptions(let package):
            package.discard()
        default:
            break
        }
    }
}


// The database cannot be opened, so no native Anki backup can be taken from it.
extension PackageImportModel {
    @concurrent
    public static func restoreAfterFailedOpen(
        from source: URL,
        core: CoreClient,
        location: CollectionLocation,
        backupFolder: URL
    ) async throws {
        guard PackageKind(fileExtension: source.pathExtension) == .collectionPackage else { throw NotAPackage() }
        let package = try await PackageFile.stage(source)
        defer { package.discard() }

        let manager = FileManager.default
        try manager.createDirectory(at: location.mediaFolder, withIntermediateDirectories: true)
        let collection = location.collectionFile
        let sidecars = ["-wal", "-shm"].map { URL(fileURLWithPath: collection.path + $0) }
        if manager.fileExists(atPath: collection.path) {
            let archive = backupFolder.appendingPathComponent("Recovery", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try manager.createDirectory(at: archive, withIntermediateDirectories: true)
            for url in [collection] + sidecars where manager.fileExists(atPath: url.path) {
                try manager.copyItem(at: url, to: archive.appendingPathComponent(url.lastPathComponent))
            }
        }

        try await core.importCollectionPackage(location.importRequest(from: package))
        for file in sidecars where manager.fileExists(atPath: file.path) {
            try manager.removeItem(at: file)
        }
    }
}

private extension CollectionLocation {
    func importRequest(from package: PackageFile) -> Anki_ImportExport_ImportCollectionPackageRequest {
        .with {
            $0.colPath = collectionFile.path
            $0.backupPath = package.url.path
            $0.mediaFolder = mediaFolder.path
            $0.mediaDb = mediaDatabase.path
        }
    }
}
