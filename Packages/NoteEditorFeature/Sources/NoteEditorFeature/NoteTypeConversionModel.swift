import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Observation

public struct NoteTypeMapping: Identifiable, Sendable {
    public let id: Int
    public let destination: String
    public let source: Int?
}

/// Maps the fields and card templates of existing notes through the core.
@MainActor
@Observable
public final class NoteTypeConversionModel {
    let store: CollectionStore
    private let noteIDs: [Int64]
    private var plan: Anki_Notetypes_ChangeNotetypeInfo?
    private var sourceID: Int64?
    private var isSaving = false
    private var hasCommitted = false

    public private(set) var destinations: [Choice] = []

    public init(store: CollectionStore, noteIDs: [Int64]) {
        self.store = store
        self.noteIDs = Array(Set(noteIDs)).sorted()
    }

    public var destinationID: Int64? { plan?.input.newNotetypeID }
    public var sourceName: String { plan?.oldNotetypeName ?? "" }
    public var noteCount: Int { noteIDs.count }
    public var sourceFields: [String] { plan?.oldFieldNames ?? [] }
    public var sourceTemplates: [String] { plan?.oldTemplateNames ?? [] }
    public var usesClozeOrdinals: Bool { plan?.input.isCloze == true }
    public var fieldMappings: [NoteTypeMapping] {
        mappings(names: plan?.newFieldNames ?? [], sources: plan?.input.newFields ?? [])
    }
    public var templateMappings: [NoteTypeMapping] {
        mappings(names: plan?.newTemplateNames ?? [], sources: plan?.input.newTemplates ?? [])
    }
    public var unmappedFields: [String] { unmapped(sourceFields, in: fieldMappings) }
    public var unmappedTemplates: [String] { usesClozeOrdinals ? [] : unmapped(sourceTemplates, in: templateMappings) }

    public var hasChanges: Bool {
        guard let input = plan?.input, !hasCommitted else { return false }
        return input.oldNotetypeID != input.newNotetypeID
            || !input.newFields.enumerated().allSatisfy { $0.offset == Int($0.element) }
            || !input.newTemplates.enumerated().allSatisfy { $0.offset == Int($0.element) }
    }

    public func load() async throws(CoreError) {
        guard plan == nil else { return }
        let source = try await currentSource()
        let types = try await store.core.getNotetypeNames().entries
        destinations = types.map { Choice(id: $0.id, name: $0.name) }
        sourceID = source
        try await chooseDestination(source)
    }

    public func chooseDestination(_ id: Int64) async throws(CoreError) {
        guard let sourceID, destinations.contains(where: { $0.id == id }), !isSaving, !hasCommitted else { return }
        plan = try await changeInfo(from: sourceID, to: id)
    }

    public func mapField(_ destination: Int, from source: Int?) {
        guard var plan, plan.input.newFields.indices.contains(destination), !isSaving, !hasCommitted,
              source.map(plan.oldFieldNames.indices.contains) != false else { return }
        plan.input.newFields[destination] = source.map(Int32.init) ?? -1
        self.plan = plan
    }

    public func mapTemplate(_ destination: Int, from source: Int?) {
        guard var plan, plan.input.newTemplates.indices.contains(destination), !isSaving, !hasCommitted,
              source.map(plan.oldTemplateNames.indices.contains) != false else { return }
        if let source, let previous = plan.input.newTemplates.firstIndex(of: Int32(source)) {
            plan.input.newTemplates[previous] = -1
        }
        plan.input.newTemplates[destination] = source.map(Int32.init) ?? -1
        self.plan = plan
    }

    public func preview() async throws(CoreError) -> [DraftCard] {
        guard let plan, let noteID = noteIDs.first else { return [] }
        let input = plan.input
        try await checkCurrentPlan(plan)
        var note = try await store.core.getNote(.with { $0.nid = noteID })
        guard note.notetypeID == input.oldNotetypeID else { throw changedTypesError() }
        let fields = note.fields
        note.notetypeID = input.newNotetypeID
        note.fields = input.newFields.map { source in
            fields.indices.contains(Int(source)) ? fields[Int(source)] : ""
        }
        let type = try await store.core.getNotetype(.with { $0.ntid = input.newNotetypeID })
        var existingOrdinals: Set<UInt32> = []
        for id in try await store.core.cardsOfNote(.with { $0.nid = noteID }).cids {
            let card = try await store.core.getCard(.with { $0.cid = id })
            existingOrdinals.insert(card.templateIdx)
        }
        var cards: [DraftCard] = []
        if type.config.kind == .cloze, let template = type.templates.first {
            let numbers = try await store.core.clozeNumbersInNote(note).numbers.filter { $0 > 0 }
            let ordinals = existingOrdinals.union(numbers.map { $0 - 1 })
            for ordinal in (ordinals.isEmpty ? [0] : ordinals.sorted()) {
                var cloze = template
                cloze.ord.val = ordinal
                let name = String(localized: "Card \(ordinal + 1)", bundle: .module)
                cards.append(try await DraftCard.render(
                    note: note, type: type, template: cloze, ordinal: ordinal,
                    name: name, core: store.core
                ).card)
            }
        } else {
            var first: DraftCard?
            for (index, configuration) in type.templates.enumerated() {
                let ordinal = UInt32(index)
                let source = input.isCloze ? Int32(index) : input.newTemplates[index]
                var template = configuration
                if source != Int32(index) || !existingOrdinals.contains(ordinal) { template.clearOrd() }
                let preview = try await DraftCard.render(
                    note: note, type: type, template: template, ordinal: ordinal,
                    name: template.name, core: store.core
                )
                if first == nil { first = preview.card }
                if !preview.isEmpty || (source >= 0 && existingOrdinals.contains(UInt32(source))) {
                    cards.append(preview.card)
                }
            }
            if cards.isEmpty, let first { cards = [first] }
        }
        return cards
    }

    public func save(confirmingFullSync: Bool = false) async throws(CoreError) -> NoteTypeSaveResult {
        guard let plan, hasChanges else { return .saved }
        guard !isSaving else {
            throw CoreError(kind: .invalidInput, message: String(localized: "A note type change is already in progress.", bundle: .module))
        }
        isSaving = true
        defer { isSaving = false }
        if try await store.requiresSchemaConfirmation(confirmed: confirmingFullSync) {
            return .needsFullSyncConfirmation
        }
        try await checkCurrentPlan(plan)
        var request = plan.input
        request.noteIds = noteIDs
        try await store.modify(.changeNotetype(request))
        hasCommitted = true
        return .saved
    }

    private func currentSource() async throws(CoreError) -> Int64 {
        try await store.core.getSingleNotetypeOfNotes(.with { $0.noteIds = noteIDs }).ntid
    }

    private func changeInfo(from source: Int64, to destination: Int64) async throws(CoreError) -> Anki_Notetypes_ChangeNotetypeInfo {
        try await store.core.getChangeNotetypeInfo(.with {
            $0.oldNotetypeID = source
            $0.newNotetypeID = destination
        })
    }

    private func checkCurrentPlan(_ plan: Anki_Notetypes_ChangeNotetypeInfo) async throws(CoreError) {
        guard try await currentSource() == plan.input.oldNotetypeID else { throw changedTypesError() }
        let latest = try await changeInfo(from: plan.input.oldNotetypeID, to: plan.input.newNotetypeID)
        guard latest.input.currentSchema == plan.input.currentSchema,
              latest.oldFieldNames == plan.oldFieldNames,
              latest.newFieldNames == plan.newFieldNames,
              latest.oldTemplateNames == plan.oldTemplateNames,
              latest.newTemplateNames == plan.newTemplateNames else { throw changedTypesError() }
    }

    private func changedTypesError() -> CoreError {
        CoreError(kind: .invalidInput, message: String(localized: "The collection changed. Reopen Change Note Type to create new mappings.", bundle: .module))
    }

    private func mappings(names: [String], sources: [Int32]) -> [NoteTypeMapping] {
        zip(names, sources).enumerated().map { index, mapping in
            NoteTypeMapping(id: index, destination: mapping.0, source: mapping.1 >= 0 ? Int(mapping.1) : nil)
        }
    }

    private func unmapped(_ names: [String], in mappings: [NoteTypeMapping]) -> [String] {
        let mapped = Set(mappings.compactMap(\.source))
        return names.enumerated().filter { !mapped.contains($0.offset) }.map(\.element)
    }
}
