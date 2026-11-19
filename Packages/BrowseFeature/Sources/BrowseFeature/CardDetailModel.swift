import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Observation

/// What the card detail shows about one card: its note's fields, where it
/// lives, when it is due and how it was reviewed.
public struct CardDetail: Equatable, Sendable {
    /// The note's fields in the note type's order, as plain text.
    public let fields: [NoteField]
    /// The full name of the card's deck.
    public let deck: String
    /// The deck the card came from, when it is in a filtered deck.
    public let originalDeck: String?
    public let noteType: String
    /// The name of the card template that made the card.
    public let cardTemplate: String
    public let cardID: Int64
    public let noteID: Int64
    public let preset: String
    public let added: Date
    public let firstReview: Date?
    public let latestReview: Date?
    public let ease: Double?
    public let averageSeconds: Double
    public let totalSeconds: Double
    public let memoryState: MemoryState?
    public let retrievability: Double?
    public let customData: String
    public let due: Due
    public let status: Status
    /// The current interval in days; 0 for a card not yet in review.
    public let intervalDays: Int
    public let reviewCount: Int
    public let lapseCount: Int
    /// The card's reviews, newest first.
    public let history: [Review]

    public struct MemoryState: Equatable, Sendable {
        public let stabilityDays: Double
        /// Difficulty as a fraction between 0 and 1.
        public let difficulty: Double

        init(_ state: Anki_Cards_FsrsMemoryState) {
            stabilityDays = Double(state.stability)
            difficulty = (Double(state.difficulty) - 1) / 9
        }
    }

    public struct NoteField: Equatable, Sendable {
        public let name: String
        /// The field's content reduced to one line of text by the core, with
        /// media shown by file name.
        public let text: String
    }

    public enum Due: Equatable, Sendable {
        /// A new card, studied in this position among new cards.
        case newCardPosition(Int)
        /// A card in learning or review, due on this date.
        case date(Date)
        /// Neither applies, for example a card the core cannot schedule.
        case unknown
    }

    public enum Status: Equatable, Sendable {
        case normal
        case suspended
        case buried
    }

    /// One review of the card.
    public struct Review: Equatable, Sendable {
        public let date: Date
        public let kind: Kind
        /// The rating chosen, or nil when the card was changed by hand, for
        /// example rescheduled or reset.
        public let rating: Rating?
        /// The interval given after the review, in seconds.
        public let intervalSeconds: Int
        public let previousIntervalSeconds: Int
        public let ease: Double?
        public let memoryState: MemoryState?
        public let secondsTaken: Double

        public enum Kind: Equatable, Sendable {
            case learning, review, relearning, filtered, manual, rescheduled
        }

        public enum Rating: Int, Equatable, Sendable {
            case again = 1, hard, good, easy
        }
    }
}

/// The card detail screen: everything about one card, kept current while
/// shown.
@MainActor
@Observable
public final class CardDetailModel {
    public enum State: Equatable {
        case loading
        case loaded(CardDetail)
        /// The card no longer exists, for example because its note was deleted.
        case deleted
        case failed(message: String)
    }

    public let cardID: Int64
    public private(set) var state: State = .loading

    @ObservationIgnored private let store: CollectionStore

    private static let relevantChanges: CollectionChange = [.card, .note, .deck, .notetype, .noteText, .deckConfig]

    public init(store: CollectionStore, cardID: Int64) {
        self.store = store
        self.cardID = cardID
    }

    /// Reads the card, its note and its review history from the core.
    public func refresh() async {
        do {
            let core = store.core
            let card = try await core.getCard(.with { $0.cid = cardID })
            let stats = try await core.cardStats(.with { $0.cid = cardID })
            let note = try await core.getNote(.with { $0.nid = card.noteID })
            let names = try await core.getFieldNames(.with { $0.ntid = note.notetypeID }).vals
            var fields: [CardDetail.NoteField] = []
            for (index, value) in note.fields.enumerated() {
                let text = try await core.htmlToTextLine(.with {
                    $0.text = value
                    $0.preserveMediaFilenames = true
                }).val
                fields.append(.init(name: index < names.count ? names[index] : "", text: text))
            }
            state = .loaded(CardDetail(card: card, stats: stats, fields: fields))
        } catch where error.kind == .notFoundError {
            state = .deleted
        } catch {
            state = .failed(message: error.message)
        }
    }

    /// Shows the card, then reads it again whenever the collection changes in
    /// a way that could alter it, until the calling task is cancelled.
    public func run() async {
        let changes = store.changes()
        await refresh()
        for await change in changes where !change.isDisjoint(with: Self.relevantChanges) {
            await refresh()
        }
    }
}

extension CardDetail {
    init(card: Anki_Cards_Card, stats: Anki_Stats_CardStatsResponse, fields: [NoteField]) {
        self.fields = fields
        deck = stats.deck
        originalDeck = stats.hasOriginalDeck ? stats.originalDeck : nil
        noteType = stats.notetype
        cardTemplate = stats.cardType
        cardID = stats.cardID
        noteID = stats.noteID
        preset = stats.preset
        added = Date(timeIntervalSince1970: TimeInterval(stats.added))
        firstReview = stats.hasFirstReview ? Date(timeIntervalSince1970: TimeInterval(stats.firstReview)) : nil
        latestReview = stats.hasLatestReview ? Date(timeIntervalSince1970: TimeInterval(stats.latestReview)) : nil
        ease = stats.ease > 0 && !stats.hasDesiredRetention ? Double(stats.ease) / 1_000 : nil
        averageSeconds = Double(stats.averageSecs)
        totalSeconds = Double(stats.totalSecs)
        memoryState = stats.hasMemoryState ? MemoryState(stats.memoryState) : nil
        retrievability = stats.hasFsrsRetrievability ? Double(stats.fsrsRetrievability) : nil
        customData = stats.customData
        due = if stats.hasDueDate {
            .date(Date(timeIntervalSince1970: TimeInterval(stats.dueDate)))
        } else if stats.hasDuePosition {
            .newCardPosition(Int(stats.duePosition))
        } else {
            .unknown
        }
        // Anki's queue numbers: -1 suspended, -2 buried by the scheduler,
        // -3 buried by the learner.
        status = switch card.queue {
        case -1: .suspended
        case -2, -3: .buried
        default: .normal
        }
        intervalDays = Int(stats.interval)
        reviewCount = Int(stats.reviews)
        lapseCount = Int(stats.lapses)
        history = stats.revlog.map(Review.init)
    }
}

extension CardDetail.Review {
    init(_ entry: Anki_Stats_CardStatsResponse.StatsRevlogEntry) {
        date = Date(timeIntervalSince1970: TimeInterval(entry.time))
        kind = switch entry.reviewKind {
        case .learning: .learning
        case .review: .review
        case .relearning: .relearning
        case .filtered: .filtered
        case .manual: .manual
        case .rescheduled: .rescheduled
        case .UNRECOGNIZED: .manual
        }
        rating = Rating(rawValue: Int(entry.buttonChosen))
        intervalSeconds = Int(entry.interval)
        previousIntervalSeconds = Int(entry.lastInterval)
        ease = entry.ease > 1_100 ? Double(entry.ease) / 1_000 : nil
        memoryState = entry.hasMemoryState ? CardDetail.MemoryState(entry.memoryState) : nil
        secondsTaken = Double(entry.takenSecs)
    }
}
