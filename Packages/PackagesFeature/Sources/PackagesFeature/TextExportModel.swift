import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Observation

@MainActor
@Observable
public final class TextExportModel {
    public enum Format: Hashable, Sendable { case notes, cards }

    public var format: Format = .notes
    public var deckID: Int64?
    public var includeHTML = true
    public var includeTags = true
    public var includeDeck = false
    public var includeNoteType = false
    public var includeGUID = false

    public private(set) var decks: [Anki_Decks_DeckNameId] = []
    public private(set) var exportedFile: URL?
    public private(set) var count: Int?
    public private(set) var isExporting = false
    public private(set) var error: String?

    @ObservationIgnored private let store: CollectionStore
    @ObservationIgnored private let folder: URL
    @ObservationIgnored private var cancelExport: (() -> Void)?

    public init(store: CollectionStore, folder: URL, deckID: Int64? = nil) {
        self.store = store
        self.folder = folder
        self.deckID = deckID
    }

    public func loadDecks() async {
        guard store.allowsNewProfileWork else { return }
        do {
            decks = try await store.core.getDeckNames(.with { $0.includeFiltered = true }).entries
        } catch {
            self.error = error.message
        }
    }

    public func export() async {
        guard !isExporting, store.allowsNewProfileWork else { return }
        isExporting = true
        error = nil
        count = nil
        exportedFile = nil
        defer {
            cancelExport = nil
            isExporting = false
        }

        let prefix = format == .notes ? "Hayaki Notes" : "Hayaki Cards"
        let file = folder.appendingPathComponent("\(prefix)-\(UUID().uuidString.prefix(8)).txt")
        let limit = Anki_ImportExport_ExportLimit.with {
            if let deckID {
                $0.deckID = deckID
            } else {
                $0.wholeCollection = .init()
            }
        }

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let operation = switch format {
            case .notes:
                store.core.start(.exportNoteCsv(.with {
                    $0.outPath = file.path
                    $0.withHtml = includeHTML
                    $0.withTags = includeTags
                    $0.withDeck = includeDeck
                    $0.withNotetype = includeNoteType
                    $0.withGuid = includeGUID
                    $0.limit = limit
                }))
            case .cards:
                store.core.start(.exportCardCsv(.with {
                    $0.outPath = file.path
                    $0.withHtml = includeHTML
                    $0.limit = limit
                }))
            }
            cancelExport = { operation.cancel() }
            count = try await Int(operation.result.val)
            exportedFile = file
        } catch {
            try? FileManager.default.removeItem(at: file)
            if (error as? CoreError)?.isInterrupted != true {
                self.error = error.localizedDescription
            }
        }
    }

    public func cancel() { cancelExport?() }
}
