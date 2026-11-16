import AnkiProto

/// What an operation changed in the collection, taken from the change summary
/// the core returns. Feature models refresh only when a change touches what
/// they show.
public struct CollectionChange: OptionSet, Sendable, Hashable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let card = CollectionChange(rawValue: 1 << 0)
    public static let note = CollectionChange(rawValue: 1 << 1)
    public static let deck = CollectionChange(rawValue: 1 << 2)
    public static let tag = CollectionChange(rawValue: 1 << 3)
    public static let notetype = CollectionChange(rawValue: 1 << 4)
    public static let config = CollectionChange(rawValue: 1 << 5)
    public static let deckConfig = CollectionChange(rawValue: 1 << 6)
    public static let mtime = CollectionChange(rawValue: 1 << 7)
    public static let browserTable = CollectionChange(rawValue: 1 << 8)
    public static let browserSidebar = CollectionChange(rawValue: 1 << 9)
    public static let noteText = CollectionChange(rawValue: 1 << 10)
    public static let studyQueues = CollectionChange(rawValue: 1 << 11)

    /// Everything may have changed: the collection was opened again or
    /// replaced.
    public static let everything = CollectionChange(rawValue: (1 << 12) - 1)

    public init(_ changes: Anki_Collection_OpChanges) {
        var set: CollectionChange = []
        if changes.card { set.insert(.card) }
        if changes.note { set.insert(.note) }
        if changes.deck { set.insert(.deck) }
        if changes.tag { set.insert(.tag) }
        if changes.notetype { set.insert(.notetype) }
        if changes.config { set.insert(.config) }
        if changes.deckConfig { set.insert(.deckConfig) }
        if changes.mtime { set.insert(.mtime) }
        if changes.browserTable { set.insert(.browserTable) }
        if changes.browserSidebar { set.insert(.browserSidebar) }
        if changes.noteText { set.insert(.noteText) }
        if changes.studyQueues { set.insert(.studyQueues) }
        self = set
    }
}

/// A core response that carries the core's change summary. Run calls that
/// return one through `CollectionStore.modify(_:)` so the change is signalled.
///
/// The common response types conform here. A feature whose call returns
/// another type with a `changes` field adds the conformance in its own package.
public protocol CollectionChanging: SwiftProtobuf.Message {
    var collectionChanges: Anki_Collection_OpChanges { get }
}

extension Anki_Collection_OpChanges: CollectionChanging {
    public var collectionChanges: Anki_Collection_OpChanges { self }
}

extension Anki_Collection_OpChangesWithCount: CollectionChanging {
    public var collectionChanges: Anki_Collection_OpChanges { changes }
}

extension Anki_Collection_OpChangesWithId: CollectionChanging {
    public var collectionChanges: Anki_Collection_OpChanges { changes }
}

extension Anki_Collection_OpChangesAfterUndo: CollectionChanging {
    public var collectionChanges: Anki_Collection_OpChanges { changes }
}

extension Anki_Collection_OpChangesOnly: CollectionChanging {
    public var collectionChanges: Anki_Collection_OpChanges { changes }
}

extension Anki_Notes_AddNoteResponse: CollectionChanging {
    public var collectionChanges: Anki_Collection_OpChanges { changes.changes }
}

extension Anki_Notes_AddNotesResponse: CollectionChanging {
    public var collectionChanges: Anki_Collection_OpChanges { changes }
}

extension Anki_ImportExport_ImportResponse: CollectionChanging {
    public var collectionChanges: Anki_Collection_OpChanges { changes }
}
