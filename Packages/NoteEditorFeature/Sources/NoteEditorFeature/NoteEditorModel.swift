import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Observation

/// A note type or deck the learner can choose in the editor.
public struct Choice: Identifiable, Equatable, Sendable {
    public let id: Int64
    /// The full name; for a deck, with its parents, such as "Languages::Spanish".
    public let name: String
}

/// A note that was added.
public struct AddedNote: Equatable, Sendable {
    public let noteID: Int64
    /// How many cards its note type made from it.
    public let cardCount: Int
}

/// Why the core's check refuses a note.
public enum AddProblem: Equatable, Sendable {
    case firstFieldEmpty
    /// A cloze deletion in a note whose note type is not a cloze type.
    case clozeOutsideClozeNotetype
    /// A cloze deletion in a field the cloze note type does not use for clozes.
    case clozeOutsideClozeField
}

/// Something the learner may well not intend, reported by the core's check.
/// The note is added only once the learner confirms it.
public enum AddWarning: Equatable, Sendable {
    /// Another note of the same note type has the same first field.
    case duplicate
    /// A cloze note without any cloze deletion.
    case noClozeDeletions
}

public enum AddOutcome: Equatable, Sendable {
    case added(AddedNote)
    case refused(AddProblem)
    case needsConfirmation(AddWarning)
    case failed(message: String)
}

public enum EditOutcome: Equatable, Sendable {
    case saved
    case refused(AddProblem)
    case needsConfirmation(AddWarning)
    case failed(message: String)
}

/// The note editor: edits an existing note or builds a note of a chosen note type, with fields, tags
/// and images, and adds it to a chosen deck.
///
/// The note type and deck start as the ones last added with, which the core
/// remembers in the collection (as desktop Anki does), so several notes can
/// be added in a row, and again the next time.
@MainActor
@Observable
public final class NoteEditorModel {
    public enum State: Equatable {
        case loading
        case ready
        case failed(message: String)
    }

    public private(set) var state: State = .loading
    public private(set) var notetypes: [Choice] = []
    public private(set) var decks: [Choice] = []
    public private(set) var notetypeID: Int64 = 0
    public private(set) var deckID: Int64 = 0
    public private(set) var fields: [EditableField] = []
    public private(set) var tags: [String] = []

    public let editingNoteID: Int64?
    @ObservationIgnored private let store: CollectionStore
    /// The note being built, as the core made it for the chosen note type.
    @ObservationIgnored private var note = Anki_Notes_Note()

    public init(store: CollectionStore, editingNoteID: Int64? = nil) {
        self.store = store
        self.editingNoteID = editingNoteID
    }

    public var notetypeName: String? { notetypes.first { $0.id == notetypeID }?.name }
    public var deckName: String? { decks.first { $0.id == deckID }?.name }

    /// Where the collection keeps a media file, to show an attached image.
    public func mediaFile(named name: String) -> URL {
        store.location.mediaFolder.appendingPathComponent(name)
    }

    // MARK: Loading

    /// Reads the note types and decks and starts an empty note of the note
    /// type last added with, in the deck last added to with it.
    public func load() async {
        do {
            if let editingNoteID {
                try await loadExistingNote(editingNoteID)
                state = .ready
                return
            }
            notetypes = try await notetypeChoices()
            decks = try await deckChoices()
            let defaults = try await store.core.defaultsForAdding(.init())
            var notetype = defaults.notetypeID
            if let last = await lastNotetypeAddedWith(), notetypes.contains(where: { $0.id == last }) {
                notetype = last
            } else if !notetypes.contains(where: { $0.id == notetype }), let first = notetypes.first {
                notetype = first.id
            }
            let lastDeck = try await store.core.defaultDeckForNotetype(.with { $0.ntid = notetype }).did
            deckID = decks.contains { $0.id == lastDeck } ? lastDeck : defaults.deckID
            try await startNote(notetypeID: notetype)
            state = .ready
        } catch {
            state = .failed(message: error.message)
        }
    }

    private func loadExistingNote(_ id: Int64) async throws(CoreError) {
        note = try await store.core.getNote(.with { $0.nid = id })
        let type = try await store.core.getNotetype(.with { $0.ntid = note.notetypeID })
        notetypeID = type.id
        notetypes = [Choice(id: type.id, name: type.name)]
        fields = zip(type.fields.map(\.name), note.fields).map { EditableField(name: $0, storedContent: $1) }
        tags = note.tags
    }

    /// Every note type except Image Occlusion, whose notes are made with an
    /// occlusion editor rather than by filling in fields.
    private func notetypeChoices() async throws(CoreError) -> [Choice] {
        var choices: [Choice] = []
        for entry in try await store.core.getNotetypeNames().entries {
            let notetype = try await store.core.getNotetype(.with { $0.ntid = entry.id })
            if notetype.config.originalStockKind != .imageOcclusion {
                choices.append(Choice(id: entry.id, name: entry.name))
            }
        }
        return choices
    }

    /// Normal decks; filtered decks cannot be added to.
    private func deckChoices() async throws(CoreError) -> [Choice] {
        try await store.core.getDeckNames(.with {
            $0.skipEmptyDefault = false
            $0.includeFiltered = false
        }).entries.map { Choice(id: $0.id, name: $0.name) }
    }

    /// The note type the core recorded as last added with ("curModel", which
    /// desktop Anki and AnkiDroid share), if any.
    private func lastNotetypeAddedWith() async -> Int64? {
        guard let json = try? await store.core.getConfigJson(.with { $0.val = "curModel" }).json else {
            return nil
        }
        return try? JSONDecoder().decode(Int64.self, from: json)
    }

    private func startNote(notetypeID: Int64) async throws(CoreError) {
        let id = Anki_Notetypes_NotetypeId.with { $0.ntid = notetypeID }
        let names = try await store.core.getFieldNames(id).vals
        note = try await store.core.newNote(id)
        self.notetypeID = notetypeID
        fields = zip(names, note.fields).map { EditableField(name: $0, storedContent: $1) }
    }

    // MARK: Choosing

    /// Switches to another note type. What was typed and attached is carried
    /// over field by field, in order; fields beyond the new type's are dropped.
    public func selectNotetype(_ id: Int64) async {
        guard editingNoteID == nil, id != notetypeID else { return }
        let previous = fields
        do {
            try await startNote(notetypeID: id)
        } catch {
            state = .failed(message: error.message)
            return
        }
        for (index, old) in previous.enumerated() where index < fields.count && old.isEdited {
            fields[index].setMarkup(old.content)
        }
    }

    public func selectDeck(_ id: Int64) {
        guard editingNoteID == nil else { return }
        deckID = id
    }

    // MARK: Editing

    public func setText(_ text: String, ofField index: Int) {
        guard fields.indices.contains(index) else { return }
        fields[index].setText(text)
    }

    public func setMarkup(_ markup: String, ofField index: Int) {
        guard fields.indices.contains(index) else { return }
        fields[index].setMarkup(markup)
    }

    /// Adds tags typed by the learner; several may be given, separated by
    /// spaces. A tag the note already has, in any case, is not added again.
    public func addTags(_ input: String) {
        for tag in input.split(whereSeparator: \.isWhitespace).map(String.init) {
            if !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                tags.append(tag)
            }
        }
    }

    public func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    /// Stores an image (for example a photo from the library) in the
    /// collection's media through the core and attaches it to a field.
    /// Formats other than JPEG, PNG, GIF and WebP, such as the iPhone's HEIC,
    /// are converted to JPEG so the card shows on every Anki client.
    public func attachImage(_ data: Data, toField index: Int) async throws(AttachImageError) {
        guard fields.indices.contains(index) else { return }
        guard let image = ImageMedia(data: data) else { throw .notAnImage }
        do {
            let stored = try await store.core.addMediaFile(.with {
                $0.desiredName = image.fileName
                $0.data = image.data
            }).val
            fields[index].attachImage(named: stored)
        } catch {
            throw .notStored(message: error.message)
        }
    }

    public func removeImage(named name: String, fromField index: Int) {
        guard fields.indices.contains(index) else { return }
        fields[index].removeImage(named: name)
    }

    /// Saves the current draft to the existing note, preserving its identity.
    public func save(confirming accepted: AddWarning? = nil) async -> EditOutcome {
        guard let editingNoteID, state == .ready else {
            return .failed(message: String(localized: "Could Not Save the Note", bundle: .module))
        }
        do {
            // Keep fields and tags changed elsewhere since this editor opened
            // when the learner left them alone.
            var candidate = try await store.core.getNote(.with { $0.nid = editingNoteID })
            guard candidate.notetypeID == note.notetypeID, candidate.fields.count == fields.count else {
                return .failed(message: String(localized: "The note type changed. Reopen the editor to edit the note.", bundle: .module))
            }
            let currentFields = candidate.fields
            let currentTags = candidate.tags
            for (index, field) in fields.enumerated() where field.isEdited {
                candidate.fields[index] = field.content
            }
            if tags != note.tags { candidate.tags = tags }
            if candidate.fields.elementsEqual(currentFields, by: { $0.utf8.elementsEqual($1.utf8) }),
               candidate.tags == currentTags {
                return .saved
            }

            let changedFirstField = !candidate.fields[0].utf8.elementsEqual(currentFields[0].utf8)
            switch try await validate(candidate, confirming: accepted) {
            case .refused(.firstFieldEmpty) where !changedFirstField: break
            case .warning(.duplicate) where !changedFirstField: break
            case .valid: break
            case .refused(let problem): return .refused(problem)
            case .warning(let warning): return .needsConfirmation(warning)
            }
            let updated = candidate
            try await store.modify(.updateNotes(.with { $0.notes = [updated] }))
            return .saved
        } catch {
            return .failed(message: error.message)
        }
    }

    /// Deletes the note and its cards after the learner confirms deletion.
    public func delete() async throws(CoreError) {
        guard let editingNoteID, state == .ready else { return }
        try await store.modify(.removeNotes(.with { $0.noteIds = [editingNoteID] }))
    }

    private var draft: Anki_Notes_Note {
        var draft = note
        draft.fields = fields.map(\.content)
        draft.tags = tags
        return draft
    }

    // MARK: Adding

    /// Adds the note if the core's check allows it. A warning the learner
    /// has seen and accepted is passed as `confirming`, and then does not
    /// stop the note again. After adding, the fields are emptied for the next
    /// note; note type, deck and tags stay.
    public func add(confirming accepted: AddWarning? = nil) async -> AddOutcome {
        guard editingNoteID == nil, state == .ready else {
            return .failed(message: String(localized: "Could Not Add the Note", bundle: .module))
        }
        let candidate = draft
        do {
            switch try await validate(candidate, confirming: accepted) {
            case .valid: break
            case .refused(let problem): return .refused(problem)
            case .warning(let warning): return .needsConfirmation(warning)
            }
            let response = try await store.modify(.addNote(.with {
                $0.note = candidate
                $0.deckID = deckID
            }))
            let cards = try await store.core.cardsOfNote(.with { $0.nid = response.noteID }).cids
            try await startNote(notetypeID: notetypeID)
            return .added(AddedNote(noteID: response.noteID, cardCount: cards.count))
        } catch {
            return .failed(message: error.message)
        }
    }

    private enum Validation {
        case valid
        case refused(AddProblem)
        case warning(AddWarning)
    }

    private func validate(_ candidate: Anki_Notes_Note, confirming accepted: AddWarning?) async throws(CoreError) -> Validation {
        switch try await store.core.noteFieldsCheck(candidate).state {
        case .empty: .refused(.firstFieldEmpty)
        case .notetypeNotCloze: .refused(.clozeOutsideClozeNotetype)
        case .fieldNotCloze: .refused(.clozeOutsideClozeField)
        case .duplicate where accepted != .duplicate: .warning(.duplicate)
        case .missingCloze where accepted != .noClozeDeletions: .warning(.noClozeDeletions)
        case .normal, .duplicate, .missingCloze, .UNRECOGNIZED: .valid
        }
    }
}
