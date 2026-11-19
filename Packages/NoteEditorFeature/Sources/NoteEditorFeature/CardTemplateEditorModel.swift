import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Observation
import StudyFeature

public enum TemplateSource: String, Hashable, Sendable {
    case front
    case back
    case styling
    case browserFront
    case browserBack
}

/// A collection-backed draft for a note type's templates and shared styling.
@MainActor
@Observable
public final class CardTemplateEditorModel {
    let store: CollectionStore
    let noteTypeID: Int64

    public private(set) var draft: Anki_Notetypes_Notetype?
    public private(set) var selectedTemplate: Int
    private var original: Anki_Notetypes_Notetype?

    public init(store: CollectionStore, noteTypeID: Int64, initialTemplate: Int = 0) {
        self.store = store
        self.noteTypeID = noteTypeID
        selectedTemplate = initialTemplate
    }

    public func load() async throws(CoreError) {
        guard draft == nil else { return }
        let type = try await store.core.getNotetype(.with { $0.ntid = noteTypeID })
        original = type
        draft = type
        if !type.templates.indices.contains(selectedTemplate) { selectedTemplate = 0 }
    }

    public var hasChanges: Bool { original != draft }
    public var isCloze: Bool { draft?.config.kind == .cloze }

    var template: Anki_Notetypes_Notetype.Template? {
        guard let draft, draft.templates.indices.contains(selectedTemplate) else { return nil }
        return draft.templates[selectedTemplate]
    }

    public func selectTemplate(_ index: Int) {
        guard draft?.templates.indices.contains(index) == true else { return }
        selectedTemplate = index
    }

    public func source(for part: TemplateSource) -> String {
        switch part {
        case .front: template?.config.qFormat ?? ""
        case .back: template?.config.aFormat ?? ""
        case .styling: draft?.config.css ?? ""
        case .browserFront: template?.config.qFormatBrowser ?? ""
        case .browserBack: template?.config.aFormatBrowser ?? ""
        }
    }

    public func setSource(_ source: String, for part: TemplateSource) {
        guard template != nil else { return }
        switch part {
        case .front: draft?.templates[selectedTemplate].config.qFormat = source
        case .back: draft?.templates[selectedTemplate].config.aFormat = source
        case .styling: draft?.config.css = source
        case .browserFront: draft?.templates[selectedTemplate].config.qFormatBrowser = source
        case .browserBack: draft?.templates[selectedTemplate].config.aFormatBrowser = source
        }
    }

    public func addTemplate() {
        guard let draft, let template, !isCloze else { return }
        var number = draft.templates.count + 1
        var name = templateName(number)
        while draft.templates.contains(where: { $0.name == name }) {
            number += 1
            name = templateName(number)
        }
        var added = Anki_Notetypes_Notetype.Template()
        added.name = name
        added.config.qFormat = template.config.qFormat
        added.config.aFormat = template.config.aFormat
        if draft.templates.count == 1 {
            let answer = template.config.aFormat
            if let separator = answer.range(of: "<hr id=answer>") {
                added.config.qFormat = answer[separator.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                added.config.qFormat = answer.replacingOccurrences(of: "{{FrontSide}}", with: "")
            }
            added.config.aFormat = "{{FrontSide}}\n\n<hr id=answer>\n\n" + template.config.qFormat
        }
        self.draft?.templates.append(added)
        selectedTemplate = draft.templates.count
    }

    private func templateName(_ number: Int) -> String {
        String(localized: "Card \(number)", bundle: .module)
    }

    public func renameTemplate(_ input: String) throws(CoreError) {
        guard let draft else { return }
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
        guard !name.isEmpty else {
            throw CoreError(kind: .invalidInput, message: String(localized: "Enter a card template name.", bundle: .module))
        }
        if draft.templates.enumerated().contains(where: {
            $0.offset != selectedTemplate && $0.element.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            throw CoreError(kind: .invalidInput, message: String(localized: "A card template already has that name.", bundle: .module))
        }
        self.draft?.templates[selectedTemplate].name = name
    }

    public func moveTemplate(to index: Int) {
        guard var draft, draft.templates.indices.contains(index), index != selectedTemplate else { return }
        let moved = draft.templates.remove(at: selectedTemplate)
        draft.templates.insert(moved, at: index)
        self.draft = draft
        selectedTemplate = index
    }

    public func deleteTemplate() {
        guard let draft, draft.templates.count > 1 else { return }
        self.draft?.templates.remove(at: selectedTemplate)
        selectedTemplate = min(selectedTemplate, draft.templates.count - 2)
    }

    public func setDeckOverride(_ deckID: Int64) {
        draft?.templates[selectedTemplate].config.targetDeckID = deckID
    }

    public func save(confirmingFullSync: Bool = false) async throws(CoreError) -> NoteTypeSaveResult {
        guard let original, let draft, original != draft else { return .saved }
        let changesSchema = draft.templates.map { $0.hasOrd ? $0.ord.val : nil } != original.templates.map { $0.ord.val }
        if changesSchema, try await store.requiresSchemaConfirmation(confirmed: confirmingFullSync) {
            return .needsFullSyncConfirmation
        }
        try await checkCurrentType()
        try await store.modify(.updateNotetype(draft))
        let saved = (try? await store.core.getNotetype(.with { $0.ntid = noteTypeID })) ?? draft
        self.original = saved
        self.draft = saved
        return .saved
    }

    func restore(
        to kind: Anki_Notetypes_StockNotetype.Kind? = nil,
        confirmingFullSync: Bool = false
    ) async throws(CoreError) -> NoteTypeSaveResult {
        if try await store.requiresSchemaConfirmation(confirmed: confirmingFullSync) {
            return .needsFullSyncConfirmation
        }
        try await checkCurrentType()
        try await store.modify(.restoreNotetypeToStock(.with {
            $0.notetypeID.ntid = noteTypeID
            if let kind { $0.forceKind = kind }
        }))
        return .saved
    }

    private func checkCurrentType() async throws(CoreError) {
        let current = try await store.core.getNotetype(.with { $0.ntid = noteTypeID })
        guard current == original else {
            throw CoreError(kind: .invalidInput, message: String(localized: "The note type changed. Reopen the template editor.", bundle: .module))
        }
    }

    public func preview(browser: Bool = false) async throws(CoreError) -> DraftCard {
        guard var template, var type = draft else {
            throw CoreError(kind: .invalidInput, message: String(localized: "Choose a card template.", bundle: .module))
        }
        let ids = try await store.core.searchNotes(.with { $0.search = "mid:\(noteTypeID)" }).ids
        let note: Anki_Notes_Note
        var ordinal = UInt32(selectedTemplate)
        if let id = ids.first {
            note = try await store.core.getNote(.with { $0.nid = id })
            if isCloze, let number = try await store.core.clozeNumbersInNote(note).numbers.filter({ $0 > 0 }).min() {
                ordinal = number - 1
                template.ord.val = ordinal
            } else if template.hasOrd, template.ord.val != ordinal {
                template.clearOrd()
            }
        } else {
            note = try await store.core.newNote(.with { $0.ntid = noteTypeID })
        }
        if browser {
            if !template.config.qFormatBrowser.isEmpty { template.config.qFormat = template.config.qFormatBrowser }
            if !template.config.aFormatBrowser.isEmpty { template.config.aFormat = template.config.aFormatBrowser }
            type.templates[selectedTemplate] = template
        }
        return try await DraftCard.render(
            note: note, type: type, template: template, ordinal: ordinal,
            name: template.name, fillEmpty: ids.isEmpty, core: store.core
        ).card
    }
}

extension DraftCard {
    static func render(
        note: Anki_Notes_Note,
        type: Anki_Notetypes_Notetype,
        template: Anki_Notetypes_Notetype.Template,
        ordinal: UInt32,
        name: String,
        fillEmpty: Bool = false,
        core: CoreClient
    ) async throws(CoreError) -> (card: DraftCard, isEmpty: Bool) {
        var rendered = try await core.renderUncommittedCard(.with {
            $0.note = note
            $0.cardOrd = ordinal
            $0.template = template
            $0.fillEmpty = fillEmpty
            $0.partialRender = true
        })
        rendered.css = type.config.css
        let content = try await CardPreviewContent(
            rendered: rendered, ordinal: ordinal, note: note, notetype: type, core: core
        )
        return (DraftCard(name: name, content: content), rendered.isEmpty)
    }
}
