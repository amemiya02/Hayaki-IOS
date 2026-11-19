import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Observation

/// Exporting the collection as a collection package, or chosen decks as a
/// deck package, with the choices desktop Anki offers.
///
/// The file is written by the core's own export code, the same code desktop
/// Anki 26.09 and AnkiDroid use, so either imports it. It goes to the export
/// folder, which the Files app shows, and from there the learner can send it
/// on through the share sheet. The export shows the core's progress and can
/// be cancelled; a cancelled or failed export leaves no file behind.
@MainActor
@Observable
public final class PackageExportModel {
    public enum Step: Equatable {
        /// The learner is choosing what to export and how.
        case choosing
        /// The core is writing the package; `progress` is its own description
        /// of the current stage, once it has reported one.
        case exporting(progress: String?)
        case finished(ExportedPackage)
        /// The learner cancelled; no file was written.
        case cancelled
        case failed(message: String)
    }

    /// What to export: the whole collection or the chosen decks.
    public var kind: PackageKind
    public let selection: ExportSelection?
    /// The decks a deck package holds, each with its subdecks.
    public var selectedDeckIDs: Set<Int64>
    public var options: ExportOptions
    /// Every deck, in the order the deck list shows them, once `loadDecks()`
    /// has run.
    public private(set) var decks: [ExportableDeck] = []
    public private(set) var step: Step = .choosing

    @ObservationIgnored private let store: CollectionStore
    @ObservationIgnored private let exportFolder: URL
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var cancelRunningOperation: (() -> Void)?
    @ObservationIgnored private var cancelRequested = false

    /// - Parameters:
    ///   - exportFolder: Where exported packages go.
    ///   - decks: Decks to export as a deck package. Empty to start with the
    ///     whole collection. As in desktop Anki, a deck chosen from its own
    ///     menu starts without scheduling, which suits sharing it.
    public init(
        store: CollectionStore,
        exportFolder: URL,
        decks: Set<Int64> = [],
        selection: ExportSelection? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.exportFolder = exportFolder
        self.now = now
        self.selection = selection
        selectedDeckIDs = decks
        let entireCollection = selection == nil && decks.isEmpty
        kind = entireCollection ? .collectionPackage : .deckPackage
        options = ExportOptions(includeScheduling: entireCollection)
    }

    /// The folder exports go to: `Exports` in the app's Documents folder,
    /// which the Files app shows.
    public nonisolated static func standardExportFolder(fileManager: FileManager = .default) throws -> URL {
        try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Exports", isDirectory: true)
    }

    /// Whether the core is writing a package now.
    public var isExporting: Bool {
        if case .exporting = step { true } else { false }
    }

    /// Whether the choices make a package: a deck package needs at least one
    /// deck.
    public var canExport: Bool {
        !isExporting && (selection.map { $0.count > 0 } ?? (kind == .collectionPackage || !selectedDeckIDs.isEmpty))
    }

    /// Lists the decks the learner can choose from.
    public func loadDecks() async {
        guard selection == nil else { return }
        decks = (try? await allDecks()) ?? decks
    }

    /// Writes the package. Ignored while an export is running or when nothing
    /// is chosen.
    public func export() async {
        guard canExport else { return }
        cancelRequested = false
        step = .exporting(progress: nil)
        defer { cancelRunningOperation = nil }
        do {
            try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
            let exported: ExportedPackage
            if let selection {
                let url = exportFolder.appendingPathComponent("selection-\(timestamp()).apkg")
                exported = try await exportDeckPackage(limit: selection.limit, to: url)
            } else {
                exported = switch kind {
                case .collectionPackage: try await exportCollection()
                case .deckPackage: try await exportDecks()
                }
            }
            step = .finished(exported)
        } catch let error as CoreError where error.isInterrupted {
            step = .cancelled
        } catch {
            step = .failed(message: error.localizedDescription)
        }
    }

    /// Stops a running export.
    public func cancel() {
        guard isExporting else { return }
        cancelRequested = true
        cancelRunningOperation?()
    }

    /// Goes back to the choices after an export ended, to export again.
    public func startOver() {
        guard !isExporting else { return }
        step = .choosing
    }

    // MARK: Exporting

    private func exportCollection() async throws -> ExportedPackage {
        let url = exportFolder.appendingPathComponent(collectionFileName())
        try throwIfCancelled()
        // The core closes the collection when it has written the package, as
        // desktop Anki's does; it is opened again straight after.
        try await store.reopening { core in
            let operation = core.start(.exportCollectionPackage(.with {
                $0.outPath = url.path
                $0.includeMedia = options.includeMedia
                $0.legacy = options.supportOlderVersions
            }))
            follow(operation)
            _ = try await operation.result
        }
        return try ExportedPackage(kind: .collectionPackage, url: url, byteCount: size(of: url), noteCount: nil)
    }

    private func exportDecks() async throws -> ExportedPackage {
        let chosen = try await allDecks().filter { selectedDeckIDs.contains($0.id) }
        guard !chosen.isEmpty else {
            throw CoreError(kind: .notFoundError, message: String(
                localized: "The chosen decks no longer exist.",
                bundle: .module,
                comment: "Shown when the decks chosen for export were deleted meanwhile."
            ))
        }
        let limit = try await limit(to: chosen)
        let url = exportFolder.appendingPathComponent(deckFileName(for: chosen))
        return try await exportDeckPackage(limit: limit, to: url)
    }

    private func exportDeckPackage(limit: Anki_ImportExport_ExportLimit, to url: URL) async throws -> ExportedPackage {
        try throwIfCancelled()
        let operation = store.core.start(.exportAnkiPackage(.with {
            $0.outPath = url.path
            $0.limit = limit
            $0.options.withScheduling = options.includeScheduling
            $0.options.withDeckConfigs = options.includeDeckPresets
            $0.options.withMedia = options.includeMedia
            $0.options.legacy = options.supportOlderVersions
        }))
        follow(operation)
        let notes = try await operation.result.val
        return try ExportedPackage(kind: .deckPackage, url: url, byteCount: size(of: url), noteCount: Int(notes))
    }

    /// What the core exports for the chosen decks: one deck with its
    /// subdecks, as desktop Anki asks for, or the cards of several.
    private func limit(to chosen: [ExportableDeck]) async throws -> Anki_ImportExport_ExportLimit {
        if chosen.count == 1 {
            return .with { $0.deckID = chosen[0].id }
        }
        // `deck:` finds a deck's cards and its subdecks' cards; the core
        // quotes the names.
        let search = try await store.core.buildSearchString(.with {
            $0.group = .with {
                $0.joiner = .or
                $0.nodes = chosen.map { deck in .with { $0.deck = deck.fullName } }
            }
        }).val
        let cardIDs = try await store.core.searchCards(.with { $0.search = search }).ids
        return .with { $0.cardIds = .with { $0.cids = cardIDs } }
    }

    private func allDecks() async throws -> [ExportableDeck] {
        try await store.core.getDeckNames(.with {
            $0.skipEmptyDefault = true
            $0.includeFiltered = true
        }).entries
            .map { ExportableDeck(id: $0.id, fullName: $0.name) }
            .sorted { lhs, rhs in
                lhs.fullName.components(separatedBy: "::")
                    .lexicographicallyPrecedes(rhs.fullName.components(separatedBy: "::")) {
                        $0.localizedStandardCompare($1) == .orderedAscending
                    }
            }
    }

    /// Lets the learner cancel `operation` and shows its progress until it
    /// ends.
    private func follow<Response>(_ operation: LongOperation<Response>) {
        cancelRunningOperation = { operation.cancel() }
        if cancelRequested { operation.cancel() }
        Task { [weak self] in
            for await progress in operation.progress {
                guard case .exporting(let text)? = progress.value else { continue }
                guard let self, self.isExporting else { return }
                self.step = .exporting(progress: text)
            }
        }
    }

    private func throwIfCancelled() throws(CoreError) {
        if cancelRequested { throw CoreError(kind: .interrupted, message: "Interrupted") }
    }

    private func size(of url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    // MARK: File names, as desktop Anki chooses them

    /// "collection-2026-11-17@09-30-00.colpkg".
    private func collectionFileName() -> String {
        let stem = String(localized: "collection", bundle: .module, comment: "Start of the file name of an exported collection package, followed by the date and time. Lowercase, as desktop Anki names it.")
        return "\(stem)-\(timestamp()).colpkg"
    }

    /// The deck's full name with characters file systems refuse replaced, as
    /// desktop Anki does ("Languages__Spanish.apkg"); for several decks,
    /// "decks-2026-11-17@09-30-00.apkg".
    private func deckFileName(for chosen: [ExportableDeck]) -> String {
        if chosen.count == 1 {
            let unsafe = CharacterSet(charactersIn: "\\/?<>:*|\"^")
            let stem = String(chosen[0].fullName.unicodeScalars.map { unsafe.contains($0) ? "_" : Character($0) })
            return "\(stem).apkg"
        }
        let stem = String(localized: "decks", bundle: .module, comment: "Start of the file name of a deck package holding several decks, followed by the date and time. Lowercase, like desktop Anki's \"collection\" file names.")
        return "\(stem)-\(timestamp()).apkg"
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd@HH-mm-ss"
        return formatter.string(from: now())
    }
}
