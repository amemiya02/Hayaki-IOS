import Foundation

/// The only collection data shared with the extensions. Each publication
/// replaces the active profile's deck information as a single file.
public struct ExtensionSnapshot: Codable, Equatable, Sendable {
    public let profileID: UUID
    public let profileName: String
    public let decks: [ExtensionDeck]
    public let noteTypes: [ExtensionNoteType]
    public let defaultDeckID: Int64?
    public let defaultNoteTypeID: Int64?

    public init(profileID: UUID, profileName: String, decks: [ExtensionDeck], noteTypes: [ExtensionNoteType],
                defaultDeckID: Int64?, defaultNoteTypeID: Int64?) {
        self.profileID = profileID
        self.profileName = profileName
        self.decks = decks
        self.noteTypes = noteTypes
        self.defaultDeckID = defaultDeckID
        self.defaultNoteTypeID = defaultNoteTypeID
    }
}

public struct ExtensionDeck: Codable, Equatable, Identifiable, Sendable {
    public let id: Int64
    public let name: String
    public let isFiltered: Bool
    public let isVisibleInWidget: Bool
    public let new: Int
    public let learning: Int
    public let review: Int

    public init(
        id: Int64, name: String, isFiltered: Bool, new: Int, learning: Int, review: Int,
        isVisibleInWidget: Bool = true
    ) {
        self.id = id
        self.name = name
        self.isFiltered = isFiltered
        self.isVisibleInWidget = isVisibleInWidget
        self.new = new
        self.learning = learning
        self.review = review
    }

    public var destination: DeckLink.Action { new + learning + review > 0 ? .study : .options }
}

public struct ExtensionNoteType: Codable, Equatable, Identifiable, Sendable {
    public let id: Int64
    public let name: String
    public let fields: [String]

    public init(id: Int64, name: String, fields: [String]) {
        self.id = id
        self.name = name
        self.fields = fields
    }
}

/// The selected theme's accent in sRGB, for the widgets.
public struct ExtensionAccent: Codable, Equatable, Sendable {
    public let lightRGB: UInt32
    public let darkRGB: UInt32

    public init(lightRGB: UInt32, darkRGB: UInt32) {
        self.lightRGB = lightRGB
        self.darkRGB = darkRGB
    }
}

public struct SharedNote: Codable, Equatable, Identifiable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case quickAdd
        case fullEditor
    }

    public let id: UUID
    public let profileID: UUID
    public let deckID: Int64
    public let noteTypeID: Int64
    public let fieldNames: [String]
    public var values: [String]
    public var mode: Mode
    public let createdAt: Date

    public init(profileID: UUID, deckID: Int64, noteTypeID: Int64,
                fieldNames: [String], values: [String], mode: Mode) {
        id = UUID()
        self.profileID = profileID
        self.deckID = deckID
        self.noteTypeID = noteTypeID
        self.fieldNames = fieldNames
        self.values = values
        self.mode = mode
        createdAt = .now
    }
}

/// The share extension writes one file per draft. The app owns their
/// consumption and neither extension can access the collection.
public struct ExtensionBridge: Sendable {
    public static let groupID = "group.io.github.amemiya02.hayaki"
    public static let deckListWidgetKind = "HayakiDeckList"
    public static let singleDeckWidgetKind = "HayakiSingleDeck"

    public static var appGroup: Self? {
        #if os(iOS)
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID).map {
            Self(directory: $0.appending(path: "Extensions", directoryHint: .isDirectory))
        }
        #else
        nil
        #endif
    }

    private let directory: URL

    public init(directory: URL) { self.directory = directory }

    private var snapshotFile: URL { directory.appending(path: "snapshot.json") }

    public func snapshot() -> ExtensionSnapshot? {
        guard let data = try? Data(contentsOf: snapshotFile) else { return nil }
        return try? JSONDecoder().decode(ExtensionSnapshot.self, from: data)
    }

    public func publish(_ snapshot: ExtensionSnapshot) throws {
        try write(snapshot, to: snapshotFile)
    }

    public func clearSnapshot() throws {
        guard FileManager.default.fileExists(atPath: snapshotFile.path) else { return }
        try FileManager.default.removeItem(at: snapshotFile)
    }

    private var accentFile: URL { directory.appending(path: "accent.json") }

    public func accent() -> ExtensionAccent? {
        guard let data = try? Data(contentsOf: accentFile) else { return nil }
        return try? JSONDecoder().decode(ExtensionAccent.self, from: data)
    }

    /// Returns whether the stored accent changed.
    @discardableResult
    public func publish(_ accent: ExtensionAccent) throws -> Bool {
        guard accent != self.accent() else { return false }
        try write(accent, to: accentFile)
        return true
    }

    public func enqueue(_ note: SharedNote) throws {
        try write(note, to: file(for: note))
    }

    public func pendingNotes(for profileID: UUID) throws -> [SharedNote] {
        let folder = inbox(for: profileID)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { file -> SharedNote? in
                guard let data = try? Data(contentsOf: file),
                      let note = try? JSONDecoder().decode(SharedNote.self, from: data),
                      note.profileID == profileID, file.lastPathComponent == self.file(for: note).lastPathComponent
                else { return nil }
                return note
            }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    public func remove(_ note: SharedNote) throws {
        try FileManager.default.removeItem(at: file(for: note))
    }

    private func inbox(for profileID: UUID) -> URL {
        directory.appending(path: "Inbox", directoryHint: .isDirectory)
            .appending(path: profileID.uuidString, directoryHint: .isDirectory)
    }

    private func file(for note: SharedNote) -> URL {
        inbox(for: note.profileID).appending(path: "\(note.id.uuidString).json")
    }

    private func write(_ value: some Encodable, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}
