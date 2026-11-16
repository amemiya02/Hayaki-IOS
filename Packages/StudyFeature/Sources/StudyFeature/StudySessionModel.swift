import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Observation

/// What a study session has come to when nothing is left to study.
public struct SessionSummary: Equatable, Sendable {
    /// Reviews made in this session.
    public let reviewed: Int
    /// The core's own description of today's studying in this collection,
    /// such as "Studied 12 cards in 3.5 minutes today (17.5s/card)", in the
    /// core's language.
    public let studiedToday: String
    /// Learning cards of the deck that come due later today, beyond Anki's
    /// learn-ahead limit.
    public let learningLaterToday: Int
}

/// A study session over one deck: the learner sees each card's question,
/// reveals the answer and rates the review, until nothing is left for today.
///
/// The cards, their order, the counts and the intervals all come from the
/// core's queue for the deck (and its child decks); every answer goes to the
/// core through `CollectionStore.modify(_:)`, so the deck list and other
/// screens see the change.
@MainActor
@Observable
public final class StudySessionModel {
    public enum State: Equatable {
        case loading
        /// The card's question side is shown.
        case question(StudyCard)
        /// The card's answer side is shown, with the rating buttons.
        case answer(StudyCard)
        /// Nothing is left to study in the deck today.
        case finished(SessionSummary)
        case failed(message: String)

        public var question: StudyCard? {
            if case .question(let card) = self { card } else { nil }
        }

        public var answer: StudyCard? {
            if case .answer(let card) = self { card } else { nil }
        }

        public var finished: SessionSummary? {
            if case .finished(let summary) = self { summary } else { nil }
        }

        /// The card shown, whichever side.
        public var card: StudyCard? {
            question ?? answer
        }
    }

    public private(set) var state: State = .loading
    /// The new, learning and due cards left in the deck today.
    public private(set) var counts = StudyCounts(new: 0, learning: 0, due: 0)
    /// Reviews made in this session so far.
    public private(set) var reviewedCount = 0
    /// Whether an answer is being sent to the core, so another one is not.
    public private(set) var isAnswering = false

    @ObservationIgnored private let store: CollectionStore
    public let deckID: Int64
    /// When the current card's question was shown, for the time the review
    /// took.
    @ObservationIgnored private var questionShownAt = ContinuousClock.now
    /// The longest time a review may count as taking, from each deck's
    /// options, by deck id.
    @ObservationIgnored private var answerTimeCaps: [Int64: Duration] = [:]

    public init(store: CollectionStore, deckID: Int64) {
        self.store = store
        self.deckID = deckID
    }

    /// Makes the deck the one being studied and shows its first card, or the
    /// finished state when it has nothing left today.
    public func start() async {
        do {
            // The core's queue is the current deck's.
            try await store.modify(.setCurrentDeck(.with { $0.did = deckID }))
        } catch {
            state = .failed(message: error.message)
            return
        }
        await showNextCard()
    }

    /// Starts the session, then keeps the shown card current until the
    /// calling task is cancelled: when its note or note type is edited (for
    /// example from the study screen), the same card and side are drawn
    /// again with the new content. The study screen runs this in its `.task`.
    public func run() async {
        // Subscribed before starting, so no change in between is missed.
        let changes = store.changes()
        if case .loading = state {
            await start()
        }
        for await change in changes where !change.isDisjoint(with: [.note, .noteText, .notetype]) {
            await redrawShownCard()
        }
    }

    private func redrawShownCard() async {
        guard let card = state.card else { return }
        do {
            let redrawn = try await card.redrawn(core: store.core)
            // The learner may have moved on meanwhile.
            switch state {
            case .question(let shown) where shown.id == card.id: state = .question(redrawn)
            case .answer(let shown) where shown.id == card.id: state = .answer(redrawn)
            default: break
            }
        } catch {
            state = .failed(message: error.message)
        }
    }

    /// Shows the question side of the card the core puts next in the queue,
    /// or the finished state when there is none. Call it after anything that
    /// changes the queue, such as undoing, burying or suspending.
    public func showNextCard() async {
        do {
            let queued = try await store.core.getQueuedCards(.with { $0.fetchLimit = 1 })
            counts = StudyCounts(queued)
            if let next = queued.cards.first {
                let card = try await StudyCard.render(next, core: store.core)
                state = .question(card)
                questionShownAt = .now
            } else {
                state = .finished(try await summary())
            }
        } catch {
            state = .failed(message: error.message)
        }
    }

    /// Turns the card over to its answer side.
    public func showAnswer() {
        guard case .question(let card) = state else { return }
        state = .answer(card)
    }

    /// Rates the review of the card whose answer is shown, sends it to the
    /// core, and moves on to the next card.
    public func answer(_ rating: Rating) async {
        guard case .answer(let card) = state, !isAnswering else { return }
        isAnswering = true
        defer { isAnswering = false }
        do {
            let taken = min(ContinuousClock.now - questionShownAt, try await answerTimeCap(for: card))
            let newState: Anki_Scheduler_SchedulingState = switch rating {
            case .again: card.states.again
            case .hard: card.states.hard
            case .good: card.states.good
            case .easy: card.states.easy
            }
            try await store.modify(.answerCard(.with {
                $0.cardID = card.id
                $0.currentState = card.states.current
                $0.newState = newState
                $0.rating = rating.proto
                $0.answeredAtMillis = Int64(Date().timeIntervalSince1970 * 1000)
                $0.millisecondsTaken = UInt32(taken.components.seconds * 1000
                    + taken.components.attoseconds / 1_000_000_000_000_000)
            }))
            reviewedCount += 1
        } catch {
            state = .failed(message: error.message)
            return
        }
        await showNextCard()
    }

    private func summary() async throws(CoreError) -> SessionSummary {
        let congrats = try await store.core.congratsInfo()
        return SessionSummary(
            reviewed: reviewedCount,
            studiedToday: try await store.core.studiedToday().val.withoutIsolationMarks,
            learningLaterToday: Int(congrats.learnRemaining)
        )
    }

    /// "Maximum answer seconds" from the options of the card's home deck,
    /// as Anki caps the time a review is recorded as taking.
    private func answerTimeCap(for card: StudyCard) async throws(CoreError) -> Duration {
        if let cap = answerTimeCaps[card.homeDeckID] { return cap }
        let deck = try await store.core.getDeck(.with { $0.did = card.homeDeckID })
        let options = try await store.core.getDeckConfig(.with { $0.dcid = deck.normal.configID })
        let seconds = options.config.capAnswerTimeToSecs
        let cap = Duration.seconds(seconds > 0 ? Int(seconds) : 60)
        answerTimeCaps[card.homeDeckID] = cap
        return cap
    }
}

extension String {
    /// The core's text wraps each number in Unicode isolation marks, which
    /// are of no use in a single-language line.
    var withoutIsolationMarks: String {
        filter { $0 != "\u{2068}" && $0 != "\u{2069}" }
    }
}
