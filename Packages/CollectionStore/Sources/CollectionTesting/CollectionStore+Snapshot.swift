import AnkiCore
import AnkiProto
import CollectionStore
import Foundation

/// A learner-level picture of notes, their cards, scheduling and review
/// history, keyed by what survives a trip through a package (note GUIDs,
/// template positions, deck names), not by ids, which another collection may
/// assign differently. Two collections with equal snapshots hold the same
/// notes studied in the same way.
public struct CollectionSnapshot: Sendable, Equatable {
    /// Sorted by GUID.
    public var notes: [NoteSnapshot]

    /// What differs from `other`, one line per note or card, empty when the
    /// two are equal. Handy in `#expect(a.differences(from: b) == [])`, whose
    /// failure then says what differs.
    public func differences(from other: CollectionSnapshot) -> [String] {
        let mine = Dictionary(notes.map { ($0.guid, $0) }, uniquingKeysWith: { first, _ in first })
        let theirs = Dictionary(other.notes.map { ($0.guid, $0) }, uniquingKeysWith: { first, _ in first })
        var lines: [String] = []
        for guid in Set(mine.keys).union(theirs.keys).sorted() {
            switch (mine[guid], theirs[guid]) {
            case (let note?, nil):
                lines.append("note \(guid) only here: \(note.fields)")
            case (nil, let note?):
                lines.append("note \(guid) missing: \(note.fields)")
            case (let note?, let expected?) where note != expected:
                var withoutCards = note
                withoutCards.cards = expected.cards
                if withoutCards != expected {
                    lines.append("note \(guid): \(note.notetype) \(note.fields) \(note.tags), expected \(expected.notetype) \(expected.fields) \(expected.tags)")
                }
                if note.cards.count != expected.cards.count {
                    lines.append("note \(guid): \(note.cards.count) cards, expected \(expected.cards.count)")
                }
                for (card, expectedCard) in zip(note.cards, expected.cards) where card != expectedCard {
                    lines.append("note \(guid) card \(card.template): \(card), expected \(expectedCard)")
                }
            default:
                break
            }
        }
        return lines
    }
}

public struct NoteSnapshot: Sendable, Equatable {
    public var guid: String
    /// The note type's kind, field names and card template names. Its name is
    /// left out: importing a deck package beside a stock note type of the same
    /// name gives the imported one a suffixed name.
    public var notetype: String
    public var fields: [String]
    public var tags: [String]
    /// Sorted by template position.
    public var cards: [CardSnapshot]
}

public struct CardSnapshot: Sendable, Equatable {
    public var template: UInt32
    /// The full name of the deck the card is in.
    public var deck: String
    /// Card type and queue as the core stores them (new, learning, review,
    /// relearning; suspended and buried show in the queue).
    public var type: UInt32
    public var queue: Int32
    /// When the card is next due, from the core's card info: the moment for
    /// a card in (re)learning steps within the day, the number of days from
    /// today for a card due on a day, the position for a new card. (The core
    /// states a day's due date as now plus whole days, so the moment itself
    /// changes from call to call.)
    public var dueMoment: Int64?
    public var dueInDays: Int?
    public var duePosition: Int32?
    public var interval: UInt32
    public var easeFactor: UInt32
    public var reps: UInt32
    public var lapses: UInt32
    public var remainingSteps: UInt32
    public var flags: UInt32
    /// Oldest first.
    public var reviews: [ReviewSnapshot]
}

public struct ReviewSnapshot: Sendable, Equatable {
    /// When the review happened, in seconds.
    public var time: Int64
    public var kind: Int
    public var button: UInt32
    public var interval: UInt32
    public var lastInterval: UInt32
    public var ease: UInt32
    public var takenSeconds: Float
}

extension CollectionStore {
    /// The notes a search finds (every note for an empty search), with all
    /// their cards, scheduling and review history.
    public func snapshot(matching search: String = "") async throws -> CollectionSnapshot {
        var notetypes: [Int64: String] = [:]
        var notes: [NoteSnapshot] = []
        for noteID in try await noteIDs(matching: search) {
            let note = try await core.getNote(.with { $0.nid = noteID })
            if notetypes[note.notetypeID] == nil {
                let notetype = try await core.getNotetype(.with { $0.ntid = note.notetypeID })
                notetypes[note.notetypeID] = "\(notetype.config.kind): "
                    + notetype.fields.map(\.name).joined(separator: ", ")
                    + " / " + notetype.templates.map(\.name).joined(separator: ", ")
            }
            var cards: [CardSnapshot] = []
            for cardID in try await core.cardsOfNote(.with { $0.nid = noteID }).cids {
                let card = try await core.getCard(.with { $0.cid = cardID })
                let stats = try await core.cardStats(.with { $0.cid = cardID })
                cards.append(CardSnapshot(
                    template: card.templateIdx,
                    deck: stats.deck,
                    type: card.ctype,
                    queue: card.queue,
                    // Queue 1: learning within the day, due at a moment.
                    dueMoment: stats.hasDueDate && card.queue == 1 ? stats.dueDate : nil,
                    dueInDays: stats.hasDueDate && card.queue != 1
                        ? Int(((Double(stats.dueDate) - Date().timeIntervalSince1970) / 86_400).rounded()) : nil,
                    duePosition: stats.hasDuePosition ? stats.duePosition : nil,
                    interval: card.interval,
                    easeFactor: card.easeFactor,
                    reps: card.reps,
                    lapses: card.lapses,
                    remainingSteps: card.remainingSteps,
                    flags: card.flags,
                    reviews: stats.revlog.map {
                        ReviewSnapshot(
                            time: $0.time,
                            kind: $0.reviewKind.rawValue,
                            button: $0.buttonChosen,
                            interval: $0.interval,
                            lastInterval: $0.lastInterval,
                            ease: $0.ease,
                            takenSeconds: $0.takenSecs
                        )
                    }.sorted { $0.time < $1.time }
                ))
            }
            notes.append(NoteSnapshot(
                guid: note.guid,
                notetype: notetypes[note.notetypeID] ?? "",
                fields: note.fields,
                tags: note.tags,
                cards: cards.sorted { $0.template < $1.template }
            ))
        }
        return CollectionSnapshot(notes: notes.sorted { $0.guid < $1.guid })
    }

    /// Every file in the collection's media folder with its contents.
    public func mediaContents() throws -> [String: Data] {
        var contents: [String: Data] = [:]
        for name in try mediaFileNames() {
            contents[name] = try Data(contentsOf: location.mediaFolder.appendingPathComponent(name))
        }
        return contents
    }
}
