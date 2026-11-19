import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Observation
import StudyFeature
import UniformTypeIdentifiers

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
/// The core chooses the initial note type and deck using the collection’s
/// adding preference. Repeated additions keep the choices in this editor.
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

    public private(set) var editingNoteID: Int64?
    private let editingCardID: Int64?
    private let homeDeckID: Int64?
    public var isEditing: Bool { editingCardID != nil || editingNoteID != nil }
    public private(set) var preferredPreviewOrdinal: UInt32 = 0
    @ObservationIgnored private let store: CollectionStore
    /// The note being built, as the core made it for the chosen note type.
    @ObservationIgnored private var note = Anki_Notes_Note()
    private var notetype = Anki_Notetypes_Notetype()
    private var occlusionFields: Anki_ImageOcclusion_ImageOcclusionFieldIndexes?
    private var pendingOcclusionImage: ImageMedia?
    private var existingOcclusionImage: Data?
    private var savedOcclusionMasks: [ImageOcclusionMask] = []
    public var occlusionImageData: Data? { pendingOcclusionImage?.data ?? existingOcclusionImage }
    public private(set) var occludesInactiveMasks = false
    public private(set) var occlusionMasks: [ImageOcclusionMask] = []
    public var isImageOcclusion: Bool { occlusionFields != nil }

    public init(store: CollectionStore, editingNoteID: Int64? = nil, homeDeckID: Int64? = nil) {
        self.store = store
        self.editingNoteID = editingNoteID
        editingCardID = nil
        self.homeDeckID = homeDeckID
    }

    public init(store: CollectionStore, editingCardID: Int64) {
        self.store = store
        self.editingCardID = editingCardID
        homeDeckID = nil
    }

    public var mediaFolder: URL { store.location.mediaFolder }
    public var isCloze: Bool { notetype.config.kind == .cloze }
    public var hasChanges: Bool {
        pendingOcclusionImage != nil || fields.contains(where: \.isEdited) || tags != note.tags
    }

    public var notetypeName: String? { notetype.name.isEmpty ? nil : notetype.name }
    public var deckName: String? { decks.first { $0.id == deckID }?.name }

    /// Where the collection keeps a media file, to show an attached image.
    public func mediaFile(named name: String) -> URL {
        store.location.mediaFolder.appendingPathComponent(name)
    }

    // MARK: Loading

    /// Reads the note types and decks and starts an empty note of the note
    /// type last added with, in the deck last added to with it.
    public func load() async {
        guard state == .loading else { return }
        do throws(CoreError) {
            if let editingCardID {
                let card = try await store.core.getCard(.with { $0.cid = editingCardID })
                editingNoteID = card.noteID
                preferredPreviewOrdinal = card.templateIdx
                deckID = card.originalDeckID == 0 ? card.deckID : card.originalDeckID
            }
            if let editingNoteID {
                try await loadExistingNote(editingNoteID)
                state = .ready
                return
            }
            notetypes = try await notetypeChoices()
            decks = try await deckChoices()
            let defaults = try await store.core.defaultsForAdding(.with {
                $0.homeDeckOfCurrentReviewCard = homeDeckID ?? 0
            })
            let notetype = notetypes.first(where: { $0.id == defaults.notetypeID }) ?? notetypes.first
            guard let notetype else {
                throw CoreError(kind: .invalidInput, message: String(localized: "No note types are available.", bundle: .module))
            }
            deckID = defaults.deckID
            try await startNote(notetypeID: notetype.id)
            state = .ready
        } catch {
            state = .failed(message: error.message)
        }
    }

    private func loadExistingNote(_ id: Int64) async throws(CoreError) {
        note = try await store.core.getNote(.with { $0.nid = id })
        notetype = try await store.core.getNotetype(.with { $0.ntid = note.notetypeID })
        notetypeID = notetype.id
        notetypes = [Choice(id: notetype.id, name: notetype.name)]
        if deckID != 0 {
            let id = deckID
            if let deck = try? await store.core.getDeck(.with { $0.did = id }) {
                decks = [Choice(id: id, name: deck.name)]
            }
        }
        fields = zip(notetype.fields.map(\.name), note.fields).map { EditableField(name: $0, storedContent: $1) }
        tags = note.tags
        occlusionFields = nil
        pendingOcclusionImage = nil
        existingOcclusionImage = nil
        occlusionMasks = []
        savedOcclusionMasks = []
        occludesInactiveMasks = false
        if notetype.config.originalStockKind == .imageOcclusion {
            let typeID = notetype.id
            let indexes = try await store.core.getImageOcclusionFields(.with { $0.notetypeID = typeID }).fields
            let response = try await store.core.getImageOcclusionNote(.with { $0.noteID = id })
            guard case .note(let imageNote) = response.value else {
                throw CoreError(kind: .invalidInput, message: response.error)
            }
            occlusionFields = indexes
            existingOcclusionImage = imageNote.imageData.isEmpty ? nil : imageNote.imageData
            occlusionMasks = imageNote.occlusions.sorted { $0.ordinal < $1.ordinal }.flatMap { group in
                group.shapes.map { ImageOcclusionMask(ordinal: group.ordinal, shape: $0) }
            }
            savedOcclusionMasks = occlusionMasks
            occludesInactiveMasks = imageNote.occludeInactive
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

    private func startNote(notetypeID: Int64) async throws(CoreError) {
        let id = Anki_Notetypes_NotetypeId.with { $0.ntid = notetypeID }
        let type = try await store.core.getNotetype(id)
        let newNote = try await store.core.newNote(id)
        notetype = type
        note = newNote
        self.notetypeID = notetypeID
        fields = zip(type.fields.map(\.name), note.fields).map { EditableField(name: $0, storedContent: $1) }
    }

    // MARK: Choosing

    /// Switches to another note type. What was typed and attached is carried
    /// over field by field, in order; fields beyond the new type's are dropped.
    public func selectNotetype(_ id: Int64) async {
        guard !isEditing, id != notetypeID else { return }
        let previous = fields.filter { field in
            guard let indexes = occlusionFields else { return true }
            return field.name != fields[Int(indexes.occlusions)].name && field.name != fields[Int(indexes.image)].name
        }
        do {
            try await startNote(notetypeID: id)
        } catch {
            state = .failed(message: error.message)
            return
        }
        occlusionFields = nil
        pendingOcclusionImage = nil
        occlusionMasks = []
        occludesInactiveMasks = false
        for (index, old) in previous.enumerated() where index < fields.count && !old.content.isEmpty {
            fields[index].setMarkup(old.content)
        }
    }

    public func selectDeck(_ id: Int64) {
        guard !isEditing else { return }
        deckID = id
    }

    /// Whether the note type pins this field when adding several notes.
    public func isSticky(_ index: Int) -> Bool {
        notetype.fields.indices.contains(index) && notetype.fields[index].config.sticky
    }

    /// Sets the note type's sticky flag, shared across Anki clients.
    public func setSticky(_ sticky: Bool, ofField index: Int) async throws(CoreError) {
        guard !isEditing, notetype.fields.indices.contains(index), isSticky(index) != sticky else { return }
        let id = notetypeID
        var latest = try await currentTypeWithSameFields()
        latest.fields[index].config.sticky = sticky
        try await store.modify(.updateNotetype(latest))
        if notetypeID == id { notetype = latest }
    }

    // MARK: Image Occlusion

    /// Begins a new image occlusion draft. The image is written when the note is added.
    public func startImageOcclusion(with data: Data, notetypeID requestedType: Int64? = nil) async throws(CoreError) {
        guard !isEditing, state == .ready, let image = ImageMedia(data: data) else {
            throw CoreError(kind: .invalidInput, message: String(localized: "Choose a readable image.", bundle: .module))
        }
        try await store.modify(.addImageOcclusionNotetype())
        let entries = try await store.core.getNotetypeNames().entries
        var selected = requestedType
        if selected == nil {
            for entry in entries {
                let type = try await store.core.getNotetype(.with { $0.ntid = entry.id })
                if type.config.originalStockKind == .imageOcclusion {
                    selected = entry.id
                    break
                }
            }
        }
        guard let selected else { throw missingOcclusionType }
        let type = try await store.core.getNotetype(.with { $0.ntid = selected })
        guard type.config.originalStockKind == .imageOcclusion else { throw missingOcclusionType }
        let indexes = try await store.core.getImageOcclusionFields(.with { $0.notetypeID = selected }).fields
        let existingTypeID = notetypeID
        if selected != existingTypeID {
            try await startNote(notetypeID: selected)
            occlusionMasks = []
            occludesInactiveMasks = false
        }
        occlusionFields = indexes
        pendingOcclusionImage = image
    }

    public func addOcclusionMask(in rect: CGRect, ellipse: Bool = false) {
        guard isImageOcclusion else { return }
        let rect = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !rect.isNull, rect.width > 0.0001, rect.height > 0.0001 else { return }
        guard let ordinal = nextOcclusionOrdinal() else { return }
        occlusionMasks.append(ImageOcclusionMask(ordinal: ordinal, rect: rect, ellipse: ellipse))
        updateOcclusionMarkup()
    }

    func addOcclusionPolygon(_ points: [CGPoint]) {
        guard points.count > 2, let ordinal = nextOcclusionOrdinal() else { return }
        let mask = ImageOcclusionMask(ordinal: ordinal, points: points)
        guard mask.rect.width > 0.0001, mask.rect.height > 0.0001 else { return }
        occlusionMasks.append(mask)
        updateOcclusionMarkup()
    }

    func addOcclusionLabel(_ label: String, at point: CGPoint) {
        guard let label = Self.occlusionLabel(label) else { return }
        occlusionMasks.append(ImageOcclusionMask(label: label, point: point))
        updateOcclusionMarkup()
    }

    func updateOcclusionLabel(_ id: UUID, label: String) {
        guard let label = Self.occlusionLabel(label),
              let index = occlusionMasks.firstIndex(where: { $0.id == id && $0.kind == "text" }) else { return }
        occlusionMasks[index].set("text", label)
        updateOcclusionMarkup()
    }

    private static func occlusionLabel(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // Separate closing delimiters without introducing a visible character.
        return text.replacingOccurrences(of: "}}", with: "}\u{200B}}")
    }

    func duplicateOcclusionMasks(_ ids: Set<UUID>) {
        var copiedGroups: [UInt32: UInt32] = [:]
        for source in occlusionMasks where ids.contains(source.id) {
            let ordinal: UInt32
            if source.ordinal == 0 {
                ordinal = 0
            } else if let group = copiedGroups[source.ordinal] {
                ordinal = group
            } else if let next = nextOcclusionOrdinal() {
                ordinal = next
                copiedGroups[source.ordinal] = next
            } else {
                break
            }
            let rect = source.rect
            var copy = ImageOcclusionMask(ordinal: ordinal, shape: source.shape)
            copy.setRect(rect.offsetBy(dx: rect.maxX < 0.97 ? 0.03 : -0.03, dy: rect.maxY < 0.97 ? 0.03 : -0.03))
            occlusionMasks.append(copy)
        }
        updateOcclusionMarkup()
    }

    private func nextOcclusionOrdinal() -> UInt32? {
        let ordinals = Set(occlusionMasks.map(\.ordinal))
        return (1...UInt32(UInt16.max)).first { !ordinals.contains($0) }
    }

    func setOcclusionMasks(_ masks: [ImageOcclusionMask]) {
        occlusionMasks = masks
        updateOcclusionMarkup()
    }

    func groupOcclusionMasks(_ ids: Set<UUID>) {
        guard let ordinal = occlusionMasks.filter({ ids.contains($0.id) && $0.ordinal > 0 }).map(\.ordinal).min()
        else { return }
        for index in occlusionMasks.indices where ids.contains(occlusionMasks[index].id) && occlusionMasks[index].ordinal > 0 {
            occlusionMasks[index].ordinal = ordinal
        }
        updateOcclusionMarkup()
    }

    func ungroupOcclusionMasks(_ ids: Set<UUID>) {
        for index in occlusionMasks.indices where ids.contains(occlusionMasks[index].id) {
            let ordinal = occlusionMasks[index].ordinal
            if ordinal > 0, occlusionMasks.filter({ $0.ordinal == ordinal }).count > 1,
               let next = nextOcclusionOrdinal() {
                occlusionMasks[index].ordinal = next
            }
        }
        updateOcclusionMarkup()
    }

    public func replaceOcclusionMask(_ id: UUID, with rect: CGRect) {
        let rect = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !rect.isNull, rect.width > 0.0001, rect.height > 0.0001,
              let index = occlusionMasks.firstIndex(where: { $0.id == id }) else { return }
        occlusionMasks[index].setRect(rect)
        updateOcclusionMarkup()
    }

    public func removeOcclusionMask(_ id: UUID) {
        guard let index = occlusionMasks.firstIndex(where: { $0.id == id }) else { return }
        occlusionMasks.remove(at: index)
        updateOcclusionMarkup()
    }

    public func setOccludesInactiveMasks(_ occludesInactive: Bool) {
        guard occludesInactiveMasks != occludesInactive else { return }
        occludesInactiveMasks = occludesInactive
        updateOcclusionMarkup()
    }

    func showsEditor(forField index: Int) -> Bool {
        guard let indexes = occlusionFields else { return true }
        return index != Int(indexes.occlusions) && index != Int(indexes.image)
    }

    private func updateOcclusionMarkup() {
        guard let indexes = occlusionFields else { return }
        let index = Int(indexes.occlusions)
        let savedMode = savedOcclusionMasks.contains { $0.value("oi") == "1" }
        if occlusionMasks == savedOcclusionMasks, occludesInactiveMasks == savedMode {
            setMarkup(fields[index].storedContent, ofField: index)
        } else {
            setMarkup(occlusionMasks.map { $0.cloze(occludeInactive: occludesInactiveMasks) }.joined(), ofField: index)
        }
    }

    private var missingOcclusionType: CoreError {
        CoreError(kind: .invalidInput, message: String(localized: "Could Not Open the Image Occlusion Note Type", bundle: .module))
    }

    private var needsOcclusionMask: CoreError {
        CoreError(kind: .invalidInput, message: String(localized: "Draw at least one mask to make a card.", bundle: .module))
    }

    private func addImageOcclusionNote() async throws(CoreError) -> AddedNote {
        guard let indexes = occlusionFields, let image = pendingOcclusionImage,
              occlusionMasks.contains(where: { $0.ordinal > 0 }) else { throw needsOcclusionMask }
        _ = try await currentTypeWithSameFields()
        let name = try await store.core.addMediaFile(.with {
            $0.desiredName = image.fileName
            $0.data = image.data
        }).val
        var newNote = draft
        var imageField = fields[Int(indexes.image)]
        imageField.attachImage(named: name)
        newNote.fields[Int(indexes.image)] = imageField.content
        let candidate = newNote
        let response = try await store.modify(.addNote(.with {
            $0.note = candidate
            $0.deckID = deckID
        }))
        discardDraft()
        return AddedNote(noteID: response.noteID, cardCount: Int(response.changes.count))
    }

    // MARK: Editing

    public func setText(_ text: String, ofField index: Int, replaceNewlines: Bool = true) {
        guard fields.indices.contains(index) else { return }
        fields[index].setText(text, replaceNewlines: replaceNewlines)
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
        try await attachImage(data, toField: index, asPNG: false)
    }

    public func pasteImage(_ data: Data, intoField index: Int) async throws {
        let asPNG = try await store.core.getConfigBool(.with { $0.key = .pasteImagesAsPng }).val
        try await attachImage(data, toField: index, asPNG: asPNG)
    }

    private func attachImage(_ data: Data, toField index: Int, asPNG: Bool) async throws(AttachImageError) {
        guard fields.indices.contains(index) else { return }
        guard let image = ImageMedia(data: data, asPNG: asPNG) else { throw .notAnImage }
        let stored = try await storeImage(image)
        guard fields.indices.contains(index) else { return }
        fields[index].attachImage(named: stored)
    }

    /// Uses the image preview's normalized crop and replaces the particular field reference.
    public func cropImage(named name: String, to crop: CGRect, inField index: Int) async throws {
        guard fields.indices.contains(index), fields[index].images.contains(name),
              let url = localMediaFile(named: name) else { return }
        let data = try await Self.readMediaFile(url)
        try await replaceImage(named: name, with: ImageMedia.cropped(data, to: crop), inField: index)
    }

    func replaceImage(named name: String, with data: Data, inField index: Int) async throws(AttachImageError) {
        guard fields.indices.contains(index), fields[index].images.contains(name) else { return }
        guard let image = ImageMedia(data: data) else { throw .notAnImage }
        let replacement = try await storeImage(image)
        fields[index].replaceImage(named: name, with: replacement)
    }

    private func storeImage(_ image: ImageMedia) async throws(AttachImageError) -> String {
        do {
            return try await store.core.addMediaFile(.with {
                $0.desiredName = image.fileName
                $0.data = image.data
            }).val
        } catch {
            throw .notStored(message: error.message)
        }
    }

    func localMediaFile(named name: String) -> URL? {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\")
        else { return nil }
        return mediaFile(named: name)
    }

    /// Imports a Files selection or a finished local recording into the current field.
    public func importMedia(from file: URL, toField index: Int) async throws {
        guard fields.indices.contains(index) else { return }
        let type = UTType(filenameExtension: file.pathExtension)
        let isImage = type?.conforms(to: .image) == true
        let isSoundOrVideo = type?.conforms(to: .audiovisualContent) == true
            || ["ogg", "opus", "oga", "webm"].contains(file.pathExtension.lowercased())
        guard isImage || isSoundOrVideo else {
            throw CoreError(kind: .invalidInput, message: String(localized: "Choose an image, audio, or video file.", bundle: .module))
        }
        let data = try await Self.readMediaFile(file)
        guard !data.isEmpty else {
            throw CoreError(kind: .invalidInput, message: String(localized: "The selected file is empty.", bundle: .module))
        }
        if isImage {
            try await attachImage(data, toField: index)
        } else {
            let desiredName = file.lastPathComponent.replacingOccurrences(of: "]", with: "_")
            let name = try await store.core.addMediaFile(.with {
                $0.desiredName = desiredName
                $0.data = data
            }).val
            fields[index].attachSound(named: name)
        }
    }

    @concurrent
    static func readMediaFile(_ file: URL) async throws -> Data {
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        return try Data(contentsOf: file, options: .mappedIfSafe)
    }

    public func removeSound(named name: String, fromField index: Int) {
        guard fields.indices.contains(index) else { return }
        fields[index].removeSound(named: name)
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
            if let indexes = occlusionFields {
                if fields[Int(indexes.occlusions)].isEdited && !occlusionMasks.contains(where: { $0.ordinal > 0 }) {
                    return .failed(message: needsOcclusionMask.message)
                }
            } else {
                switch try await validate(candidate, confirming: accepted) {
                case .refused(.firstFieldEmpty) where !changedFirstField: break
                case .warning(.duplicate) where !changedFirstField: break
                case .valid: break
                case .refused(let problem): return .refused(problem)
                case .warning(let warning): return .needsConfirmation(warning)
                }
            }
            _ = try await currentTypeWithSameFields()
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

    func noteTypeConversion() -> NoteTypeConversionModel? {
        editingNoteID.map { NoteTypeConversionModel(store: store, noteIDs: [$0]) }
    }

    func discardDraft() {
        pendingOcclusionImage = nil
        if isImageOcclusion {
            occlusionMasks = savedOcclusionMasks
            occludesInactiveMasks = savedOcclusionMasks.contains { $0.value("oi") == "1" }
        }
        fields = zip(notetype.fields.map(\.name), note.fields).map { EditableField(name: $0, storedContent: $1) }
        tags = note.tags
    }

    func reloadAfterNoteTypeChange() async throws(CoreError) {
        guard let editingNoteID else { return }
        let ids = try await store.core.cardsOfNote(.with { $0.nid = editingNoteID }).cids
        let active = editingCardID.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first
        if let active {
            let card = try await store.core.getCard(.with { $0.cid = active })
            preferredPreviewOrdinal = card.templateIdx
            deckID = card.originalDeckID == 0 ? card.deckID : card.originalDeckID
        } else {
            preferredPreviewOrdinal = 0
            deckID = 0
        }
        decks = []
        try await loadExistingNote(editingNoteID)
    }

    private func currentTypeWithSameFields() async throws(CoreError) -> Anki_Notetypes_Notetype {
        let id = notetypeID
        let current = try await store.core.getNotetype(.with { $0.ntid = id })
        guard current.fields.map(\.name) == notetype.fields.map(\.name) else {
            throw CoreError(kind: .invalidInput, message: String(
                localized: "The note type changed. Reopen the editor to edit the note.", bundle: .module
            ))
        }
        return current
    }

    private var draft: Anki_Notes_Note {
        var draft = note
        draft.fields = fields.map(\.content)
        if let indexes = occlusionFields, let image = pendingOcclusionImage {
            var field = fields[Int(indexes.image)]
            field.attachImage(named: image.fileName)
            draft.fields[Int(indexes.image)] = field.content
        }
        draft.tags = tags
        return draft
    }

    // MARK: Preview

    func previewImage() -> (name: String, dataURL: String)? {
        guard let image = pendingOcclusionImage else { return nil }
        return (image.fileName, "data:\(image.mimeType);base64,\(image.data.base64EncodedString())")
    }

    /// The core renders the current draft, including unsaved changes.
    public func preview() async throws(CoreError) -> [DraftCard] {
        let draft = self.draft
        let type = try await currentTypeWithSameFields()
        let selections: [(UInt32, String, Anki_Notetypes_Notetype.Template)]
        if type.config.kind == .cloze, let template = type.templates.first {
            var ordinals = try await store.core.clozeNumbersInNote(draft).numbers.filter { $0 > 0 }.map { $0 - 1 }
            if draft.id != 0, !isImageOcclusion {
                for id in try await store.core.cardsOfNote(.with { $0.nid = draft.id }).cids {
                    let card = try await store.core.getCard(.with { $0.cid = id })
                    ordinals.append(card.templateIdx)
                }
            }
            if ordinals.isEmpty {
                guard !isImageOcclusion else { throw needsOcclusionMask }
                ordinals = [0]
            }
            selections = Set(ordinals).sorted().map { ordinal in
                // The core uses the template ordinal to find an existing card.
                // Cloze cards all use one template but each has its own ordinal.
                var clozeTemplate = template
                clozeTemplate.ord.val = ordinal
                let name = String(localized: "Card \(ordinal + 1)", bundle: .module)
                return (ordinal, name, clozeTemplate)
            }
        } else {
            selections = type.templates.enumerated().map { (UInt32($0.offset), $0.element.name, $0.element) }
        }
        var cards: [DraftCard] = []
        for (ordinal, name, template) in selections {
            let response = try await store.core.renderUncommittedCard(.with {
                $0.note = draft
                $0.cardOrd = ordinal
                $0.template = template
                $0.partialRender = true
            })
            let content = try await CardPreviewContent(
                rendered: response, ordinal: ordinal, note: draft, notetype: type, core: store.core
            )
            cards.append(DraftCard(name: name, content: content))
        }
        return cards
    }

    // MARK: Adding

    /// Adds the note if the core's check allows it. A warning the learner
    /// has seen and accepted is passed as `confirming`, and then does not
    /// stop the note again. Sticky field values, note type, deck and tags
    /// carry over to the next note.
    public func add(confirming accepted: AddWarning? = nil) async -> AddOutcome {
        guard !isEditing, state == .ready else {
            return .failed(message: String(localized: "Could Not Add the Note", bundle: .module))
        }
        let candidate = draft
        do {
            if isImageOcclusion { return .added(try await addImageOcclusionNote()) }
            switch try await validate(candidate, confirming: accepted) {
            case .valid: break
            case .refused(let problem): return .refused(problem)
            case .warning(let warning): return .needsConfirmation(warning)
            }
            _ = try await currentTypeWithSameFields()
            var next = try await store.core.newNote(.with { $0.ntid = candidate.notetypeID })
            let response = try await store.modify(.addNote(.with {
                $0.note = candidate
                $0.deckID = deckID
            }))
            next.tags = candidate.tags
            note = next
            fields = fields.enumerated().map { index, field in
                EditableField(name: field.name, storedContent: isSticky(index) ? candidate.fields[index] : "")
            }
            return .added(AddedNote(noteID: response.noteID, cardCount: Int(response.changes.count)))
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

public struct DraftCard: Identifiable, Equatable, Sendable {
    public var id: UInt32 { content.ordinal }
    public let name: String
    public let content: CardPreviewContent
}
