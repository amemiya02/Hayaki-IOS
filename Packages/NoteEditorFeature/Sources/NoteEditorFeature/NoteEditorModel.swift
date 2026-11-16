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

/// The note editor: builds a note of a chosen note type, with fields, tags
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

    @ObservationIgnored private let store: CollectionStore
    /// The note being built, as the core made it for the chosen note type.
    @ObservationIgnored private var note = Anki_Notes_Note()

    public init(store: CollectionStore) {
        self.store = store
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
        guard id != notetypeID else { return }
        let previous = fields
        do {
            try await startNote(notetypeID: id)
        } catch {
            state = .failed(message: error.message)
            return
        }
        for (index, old) in previous.enumerated() where index < fields.count && old.isEdited {
            fields[index].carryOver(old)
        }
    }

    public func selectDeck(_ id: Int64) {
        deckID = id
    }

    // MARK: Editing

    public func setText(_ text: String, ofField index: Int) {
        guard fields.indices.contains(index) else { return }
        fields[index].text = text
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

    // MARK: Adding

    /// Adds the note if the core's check allows it. A warning the learner
    /// has seen and accepted is passed as `confirming`, and then does not
    /// stop the note again. After adding, the fields are emptied for the next
    /// note; note type, deck and tags stay.
    public func add(confirming accepted: AddWarning? = nil) async -> AddOutcome {
        var candidate = note
        candidate.fields = fields.map(\.content)
        candidate.tags = tags
        do {
            switch try await store.core.noteFieldsCheck(candidate).state {
            case .normal: break
            case .empty: return .refused(.firstFieldEmpty)
            case .notetypeNotCloze: return .refused(.clozeOutsideClozeNotetype)
            case .fieldNotCloze: return .refused(.clozeOutsideClozeField)
            case .duplicate where accepted != .duplicate: return .needsConfirmation(.duplicate)
            case .missingCloze where accepted != .noClozeDeletions: return .needsConfirmation(.noClozeDeletions)
            case .duplicate, .missingCloze, .UNRECOGNIZED: break
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
}
