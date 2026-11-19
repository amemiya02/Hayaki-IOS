import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Observation

public struct TextImportSummary: Equatable, Sendable {
    public let added: Int
    public let updated: Int
    public let skipped: Int
    public let invalidRows: Int

    init(_ log: Anki_ImportExport_ImportResponse.Log) {
        // The core groups first-field matches under one key for all three policies.
        let matches = log.firstFieldMatch.count
        added = log.new.count + (log.dupeResolution == .duplicate ? matches : 0)
        updated = log.updated.count + (log.dupeResolution == .update ? matches : 0)
        skipped = log.duplicate.count + log.conflicting.count + (log.dupeResolution == .preserve ? matches : 0)
        invalidRows = log.missingNotetype.count + log.missingDeck.count + log.emptyFirstField.count
    }
}

@MainActor
@Observable
public final class TextImportModel {
    public typealias Metadata = Anki_ImportExport_CsvMetadata

    public private(set) var isPresented = false
    public private(set) var fileName: String?
    public private(set) var deckChoices: [Anki_Decks_DeckNameId] = []
    public private(set) var noteTypeChoices: [Anki_Notetypes_NotetypeNameId] = []
    public private(set) var fieldNames: [String] = []
    public private(set) var metadata: Metadata?
    public private(set) var summary: TextImportSummary?
    public private(set) var isWorking = false
    public private(set) var isImporting = false
    public private(set) var progress: String?
    public private(set) var error: String?

    @ObservationIgnored private let store: CollectionStore
    @ObservationIgnored private var staged: StagedImportFile?
    private var detected: Metadata?
    @ObservationIgnored private var cancelImport: (() -> Void)?

    public init(store: CollectionStore) {
        self.store = store
    }

    deinit { staged?.discard() }

    public func show() {
        guard store.allowsNewProfileWork else { return }
        isPresented = true
    }

    public func dismiss() {
        guard !isWorking else { return }
        isPresented = false
        clearSelection()
    }

    private func clearSelection() {
        staged?.discard()
        staged = nil
        metadata = nil
        detected = nil
        summary = nil
        progress = nil
        error = nil
        fileName = nil
    }

    public func prepare(_ source: URL) async {
        guard !isWorking, store.allowsNewProfileWork else { return }
        clearSelection()
        show()
        isWorking = true
        defer { isWorking = false }
        fileName = source.lastPathComponent

        do {
            let file = try await StagedImportFile.stage(source)
            staged = file
            let preview = try await store.core.getCsvMetadata(.with { $0.path = file.url.path })
            deckChoices = try await store.core.getDeckNames(.with { $0.includeFiltered = false }).entries
            noteTypeChoices = try await store.core.getNotetypeNames().entries
            fieldNames = try await names(of: preview)
            detected = preview
            metadata = preview
        } catch {
            staged?.discard()
            staged = nil
            self.error = error.localizedDescription
        }
    }

    public func setFieldColumn(_ column: UInt32, forField index: Int) {
        updateOptions {
            guard $0.globalNotetype.fieldColumns.indices.contains(index),
                  column <= $0.columnLabels.count else { return }
            $0.globalNotetype.fieldColumns[index] = column
        }
    }

    public func updateOptions(_ edit: (inout Metadata) -> Void) {
        guard var current = metadata, !isWorking, store.allowsNewProfileWork else { return }
        edit(&current)
        metadata = current
    }

    public func updatePreview(delimiter: Metadata.Delimiter? = nil, notetypeID: Int64? = nil, html: Bool? = nil) async {
        guard let staged, let current = metadata, !isWorking, store.allowsNewProfileWork else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            var refreshed = try await store.core.getCsvMetadata(.with {
                $0.path = staged.url.path
                $0.delimiter = delimiter ?? current.delimiter
                if let id = notetypeID {
                    $0.notetypeID = id
                } else if case .globalNotetype(let mapped) = current.notetype {
                    $0.notetypeID = mapped.id
                }
                if case .deckID(let id) = current.deck { $0.deckID = id }
                $0.isHtml = html ?? current.isHtml
            })
            refreshed.dupeResolution = current.dupeResolution
            refreshed.matchScope = current.matchScope
            refreshed.globalTags = current.globalTags
            refreshed.updatedTags = current.updatedTags
            if case .globalNotetype(let oldMapping) = current.notetype,
               oldMapping.id == refreshed.globalNotetype.id,
               oldMapping.fieldColumns.allSatisfy({ $0 <= refreshed.columnLabels.count }) {
                refreshed.globalNotetype.fieldColumns = oldMapping.fieldColumns
            }
            fieldNames = try await names(of: refreshed)
            metadata = refreshed
        } catch {
            self.error = error.message
        }
    }

    public var suggestsDeckFromFile: Bool {
        switch detected?.deck {
        case .deckColumn, .deckName: true
        default: false
        }
    }

    public var suggestsNoteTypeFromFile: Bool {
        if case .notetypeColumn = detected?.notetype { return true }
        return false
    }

    public func useFileDeck() {
        guard suggestsDeckFromFile else { return }
        updateOptions { $0.deck = detected?.deck }
    }

    public func useFileNoteType() {
        guard suggestsNoteTypeFromFile, !isWorking, store.allowsNewProfileWork else { return }
        updateOptions { $0.notetype = detected?.notetype }
        fieldNames = []
    }

    private func names(of preview: Metadata) async throws(CoreError) -> [String] {
        guard case .globalNotetype(let mapping) = preview.notetype else { return [] }
        return try await store.core.getNotetype(.with { $0.ntid = mapping.id }).fields.map(\.name)
    }

    public func startImport() async {
        guard let staged, let metadata, !isWorking, summary == nil, store.allowsNewProfileWork else { return }
        isWorking = true
        isImporting = true
        error = nil
        progress = nil
        let operation = store.core.start(.importCsv(.with {
            $0.path = staged.url.path
            $0.metadata = metadata
        }))
        cancelImport = { operation.cancel() }
        let progressTask = Task {
            for await update in operation.progress {
                if case .importing(let text)? = update.value { progress = text }
            }
        }
        defer {
            progressTask.cancel()
            cancelImport = nil
            isWorking = false
            isImporting = false
        }
        do {
            let response = try await store.modify(operation)
            summary = TextImportSummary(response.log)
            staged.discard()
            self.staged = nil
        } catch {
            if !error.isInterrupted { self.error = error.message }
        }
    }

    public func cancel() {
        cancelImport?()
    }
}
