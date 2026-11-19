import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Observation

/// What a study session has come to when nothing is left to study.
public struct SessionSummary: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case dailyLimit
        case learningLater
        case buried
        case done
    }

    public var reason: Reason {
        if dailyLimitReached { return .dailyLimit }
        if nextLearningAt != nil { return .learningLater }
        if hasBuried { return .buried }
        return .done
    }

    public let dailyLimitReached: Bool
    public let nextLearningAt: Date?
    public let hasBuried: Bool
    public let nextDayStartsAt: Date
    public let isFiltered: Bool

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
    public private(set) var previousCardID: Int64?
    public private(set) var presentationNumber = 0
    public private(set) var showsRemainingCounts = true
    public private(set) var showsRatingIntervals = true
    public private(set) var hidesAudioButtons = false
    public private(set) var interruptsAudioWhenAnswering = false
    public private(set) var currentDeckName = ""
    public private(set) var showsAnswerTimer = false
    public private(set) var timeboxLimit: Duration = .zero
    @ObservationIgnored private var timeboxBeganAt = ContinuousClock.now
    @ObservationIgnored private var timeboxReviewed = 0
    @ObservationIgnored private var revealedAt: ContinuousClock.Instant?
    private var activeOptions: CardOptions?
    /// Whether an answer is being sent to the core, so another one is not.
    public private(set) var isAnswering = false
    public private(set) var isPerformingAction = false
    public var isBusy: Bool { isAnswering || isPerformingAction }

    public private(set) var canUndo = false
    public private(set) var canRedo = false
    public private(set) var actionError: String?

    // The core assigns a new counter whenever it applies, undoes or redoes
    // a step. Keep only review counters from this session in these sets.
    @ObservationIgnored private var appliedReviews: Set<UInt32> = []
    @ObservationIgnored private var revertedReviews: Set<UInt32> = []

    @ObservationIgnored private let store: CollectionStore
    public let deckID: Int64
    /// When the current card's question was shown, for the time the review
    /// took.
    @ObservationIgnored private var questionShownAt = ContinuousClock.now
    /// The options of each card's home deck, by deck id.
    @ObservationIgnored private var cardOptions: [Int64: CardOptions] = [:]
    /// What the learner typed on the shown card, for its answer side.
    @ObservationIgnored private var typedAnswer = ""
    /// The audio options of the shown card's home deck.
    @ObservationIgnored private var audioOptions = AudioOptions()

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
        await refreshReviewerPreferences()
        restartTimebox()
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
            // Reviewer actions refresh after applying their own changes.
            guard !isPerformingAction else { continue }
            await redrawShownCard()
            await refreshUndoStatus()
        }
    }

    private func redrawShownCard() async {
        guard let card = state.card else { return }
        do {
            let redrawn = try await card.redrawn(core: store.core)
            let redrawnAnswer = try await redrawn.answering(typed: typedAnswer, core: store.core)
            // The learner may have moved on meanwhile.
            switch state {
            case .question(let shown) where shown.id == card.id: state = .question(redrawn)
            case .answer(let shown) where shown.id == card.id: state = .answer(redrawnAnswer)
            default: break
            }
        } catch where error.kind == .notFoundError {
            await showNextCard()
        } catch {
            state = .failed(message: error.message)
        }
    }

    /// Shows the question side of the card the core puts next in the queue,
    /// or the finished state when there is none. Call it after anything that
    /// changes the queue, such as undoing, burying or suspending.
    public func showNextCard() async {
        await refreshUndoStatus()
        do {
            let queued = try await store.core.getQueuedCards(.with { $0.fetchLimit = 1 })
            counts = StudyCounts(queued)
            if let next = queued.cards.first {
                let card = try await StudyCard.render(next, core: store.core)
                let settings = try await options(for: card)
                activeOptions = settings
                audioOptions = settings.audio
                showsAnswerTimer = settings.showsAnswerTimer
                currentDeckName = settings.deckName
                questionShownAt = .now
                revealedAt = nil
                presentationNumber += 1
                state = .question(card)
            } else {
                state = .finished(try await summary())
            }
        } catch {
            state = .failed(message: error.message)
        }
    }

    /// Turns the card over to its answer side. On a card that asks the
    /// learner to type the answer, the answer side shows the expected answer,
    /// as when nothing was typed.
    public func showAnswer() {
        guard case .question(let card) = state, !isBusy else { return }
        typedAnswer = ""
        revealedAt = .now
        state = .answer(card)
    }

    /// Turns the card over to its answer side, which on a card that asks the
    /// learner to type the answer shows the core's comparison of `typed`
    /// with the expected answer. Other cards ignore `typed`.
    public func showAnswer(typed: String) async {
        guard case .question(let card) = state, !isBusy else { return }
        guard card.asksForTypedAnswer else {
            showAnswer()
            return
        }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            let answered = try await card.answering(typed: typed, core: store.core)
            // The learner may have moved on meanwhile.
            guard case .question(let shown) = state, shown.id == card.id else { return }
            typedAnswer = typed
            revealedAt = .now
            state = .answer(answered)
        } catch {
            state = .failed(message: error.message)
        }
    }

    /// Rates the review of the card whose answer is shown, sends it to the
    /// core, and moves on to the next card.
    public func answer(_ rating: Rating) async {
        guard case .answer(let card) = state, !isBusy else { return }
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
            previousCardID = card.id
            if let status = try? await store.core.getUndoStatus(), !status.undo.isEmpty {
                appliedReviews.insert(status.lastStep)
            }
            revertedReviews.removeAll()
        } catch {
            state = .failed(message: error.message)
            return
        }
        await showNextCard()
    }

    /// Runs a command that acts on the study session or changes the collection.
    /// Presentation commands are handled by the reviewer after this returns false.
    @discardableResult
    public func perform(_ command: ReviewerCommand, typed: String = "") async -> Bool {
        guard !isBusy else { return false }
        if let rating = command.rating {
            guard state.answer != nil else { return false }
            await answer(rating)
            return true
        }
        if let flag = command.flag {
            guard let card = state.card else { return false }
            await setFlag(command.togglesFlag && card.flag == flag ? 0 : flag)
            return true
        }
        switch command {
        case .undo:
            guard canUndo else { return false }
            await undo()
        case .redo:
            guard canRedo else { return false }
            await redo()
        case .showAnswer:
            guard state.question != nil else { return false }
            await showAnswer(typed: typed)
        case .mark, .buryCard, .buryNote, .suspendCard, .suspendNote:
            guard state.card != nil else { return false }
            switch command {
            case .mark: await toggleMark()
            case .buryCard, .buryNote: await bury(note: command == .buryNote)
            case .suspendCard, .suspendNote: await suspend(note: command == .suspendNote)
            default: break
            }
        default:
            return false
        }
        return true
    }

    public func undo() async {
        guard canUndo else { return }
        await runAction { () async throws(CoreError) in
            let result = try await store.modify(.undo())
            if appliedReviews.remove(result.counter) != nil {
                reviewedCount -= 1
                revertedReviews.insert(result.newStatus.lastStep)
            }
            await showNextCard()
        }
    }

    public func redo() async {
        guard canRedo else { return }
        await runAction { () async throws(CoreError) in
            let result = try await store.modify(.redo())
            if revertedReviews.remove(result.counter) != nil {
                reviewedCount += 1
                appliedReviews.insert(result.newStatus.lastStep)
            }
            await showNextCard()
        }
    }

    public func bury(note: Bool) async {
        await skip(note: note, mode: .buryUser)
    }

    public func suspend(note: Bool) async {
        await skip(note: note, mode: .suspend)
    }

    private func skip(note: Bool, mode: Anki_Scheduler_BuryOrSuspendCardsRequest.Mode) async {
        guard let card = state.card else { return }
        await runAction { () async throws(CoreError) in
            try await store.modify(.buryOrSuspendCards(.with {
                if note { $0.noteIds = [card.noteID] } else { $0.cardIds = [card.id] }
                $0.mode = mode
            }))
            await showNextCard()
        }
    }

    public func unburyDeck() async {
        guard state.finished?.hasBuried == true else { return }
        await runAction { () async throws(CoreError) in
            try await store.modify(.unburyDeck(.with { $0.deckID = deckID }))
            await showNextCard()
        }
    }

    public func rebuildFinishedFilteredDeck() async {
        guard state.finished?.isFiltered == true else { return }
        await runAction { () async throws(CoreError) in
            try await store.modify(.rebuildFilteredDeck(.with { $0.did = deckID }))
            await showNextCard()
        }
    }

    public func setFlag(_ flag: UInt32) async {
        guard let card = state.card, flag < 8 else { return }
        await runAction { () async throws(CoreError) in
            try await store.modify(.setFlag(.with {
                $0.cardIds = [card.id]
                $0.flag = flag
            }))
            await redrawShownCard()
            await refreshUndoStatus()
        }
    }

    public var isCurrentNoteMarked: Bool { state.card?.isNoteMarked == true }

    public func toggleMark() async {
        guard let card = state.card else { return }
        await runAction { () async throws(CoreError) in
            var note = try await store.core.getNote(.with { $0.nid = card.noteID })
            if note.tags.contains(where: StudyCard.isMarkTag) {
                note.tags.removeAll(where: StudyCard.isMarkTag)
            } else {
                note.tags.append("marked")
            }
            let updatedNote = note
            try await store.modify(.updateNotes(.with { $0.notes = [updatedNote] }))
            await redrawShownCard()
            await refreshUndoStatus()
        }
    }

    func tags(of noteID: Int64) async throws(CoreError) -> [String] {
        try await store.core.getNote(.with { $0.nid = noteID }).tags
    }

    func setTags(_ tags: [String], on noteID: Int64) async throws(CoreError) {
        var note = try await store.core.getNote(.with { $0.nid = noteID })
        guard note.tags != tags else { return }
        note.tags = tags
        let updated = note
        try await store.modify(.updateNotes(.with { $0.notes = [updated] }))
        await refreshUndoStatus()
    }

    public func setDueDate(_ days: String) async {
        guard let card = state.card else { return }
        await runAction { () async throws(CoreError) in
            try await store.modify(.setDueDate(.with {
                $0.cardIds = [card.id]
                $0.days = days
            }))
            await showNextCard()
        }
    }

    public func resetProgress() async {
        guard let card = state.card else { return }
        await runAction { () async throws(CoreError) in
            let defaults = try await store.core.scheduleCardsAsNewDefaults(.with { $0.context = .reviewer })
            try await store.modify(.scheduleCardsAsNew(.with {
                $0.cardIds = [card.id]
                $0.log = true
                $0.restorePosition = defaults.restorePosition
                $0.resetCounts = defaults.resetCounts
                $0.context = .reviewer
            }))
            await showNextCard()
        }
    }

    public func deleteNote() async {
        guard let card = state.card else { return }
        await runAction { () async throws(CoreError) in
            try await store.modify(.removeNotes(.with { $0.cardIds = [card.id] }))
            await showNextCard()
        }
    }

    public func clearActionError() {
        actionError = nil
    }

    private func runAction(_ action: () async throws(CoreError) -> Void) async {
        guard !isBusy else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await action()
        } catch {
            actionError = error.message
        }
    }

    private func refreshUndoStatus() async {
        let status = try? await store.core.getUndoStatus()
        canUndo = status?.undo.isEmpty == false
        canRedo = status?.redo.isEmpty == false
        if !canRedo { revertedReviews.removeAll() }
    }

    private func summary() async throws(CoreError) -> SessionSummary {
        let congrats = try await store.core.congratsInfo()
        let nextDay = try await store.core.schedTimingToday().nextDayAt
        let learningDelay = congrats.secsUntilNextLearn
        let nextLearningAt = congrats.learnRemaining > 0 && learningDelay < 86_400
            ? Date.now.addingTimeInterval(Double(learningDelay))
            : nil
        return SessionSummary(
            dailyLimitReached: congrats.newRemaining || congrats.reviewRemaining,
            nextLearningAt: nextLearningAt,
            hasBuried: congrats.haveSchedBuried || congrats.haveUserBuried,
            nextDayStartsAt: Date(timeIntervalSince1970: Double(nextDay)),
            isFiltered: congrats.isFilteredDeck,
            reviewed: reviewedCount,
            studiedToday: try await store.core.studiedToday().val.withoutIsolationMarks,
            learningLaterToday: Int(congrats.learnRemaining)
        )
    }

    func existingReviewerDeckOptionsChanged() async {
        cardOptions.removeAll()
        guard let card = state.card, let options = try? await options(for: card), state.card?.id == card.id else { return }
        activeOptions = options
        audioOptions = options.audio
        showsAnswerTimer = options.showsAnswerTimer
        currentDeckName = options.deckName
    }

    public func refreshReviewerPreferences() async {
        guard let config = try? await store.core.getPreferences().reviewing else { return }
        showsRemainingCounts = config.showRemainingDueCounts
        showsRatingIntervals = config.showIntervalsOnButtons
        hidesAudioButtons = config.hideAudioPlayButtons
        interruptsAudioWhenAnswering = config.interruptAudioWhenAnswering
        timeboxLimit = .seconds(config.timeLimitSecs)
    }

    public var autoAdvancePlan: AutoAdvancePlan? {
        guard let options = activeOptions, state.card != nil else { return nil }
        let showingAnswer = state.answer != nil
        let delay = showingAnswer ? options.answerDelay : options.questionDelay
        guard delay > .zero else { return nil }
        return AutoAdvancePlan(
            delay: delay, waitForAudio: options.waitForAudio,
            command: showingAnswer ? options.answerAction : options.questionAction
        )
    }

    public func answerTimer(at now: ContinuousClock.Instant = .now) -> Duration {
        guard let options = activeOptions, state.card != nil else { return .zero }
        let end = options.stopsTimerOnAnswer ? (revealedAt ?? now) : now
        return min(max(.zero, end - questionShownAt), options.answerTimeCap)
    }

    public func restartTimebox(at now: ContinuousClock.Instant = .now) {
        timeboxBeganAt = now
        timeboxReviewed = reviewedCount
    }

    public func timeboxProgress(at now: ContinuousClock.Instant = .now) -> StudyTimebox? {
        let reviewed = reviewedCount - timeboxReviewed
        guard timeboxLimit > .zero, now - timeboxBeganAt >= timeboxLimit, reviewed > 0 else { return nil }
        return StudyTimebox(reviewed: reviewed, limit: timeboxLimit)
    }

    /// "Maximum answer seconds" from the options of the card's home deck,
    /// as Anki caps the time a review is recorded as taking.
    private func answerTimeCap(for card: StudyCard) async throws(CoreError) -> Duration {
        try await options(for: card).answerTimeCap
    }

    /// The options of a card's home deck that studying it follows, read once
    /// per deck in a session.
    private func options(for card: StudyCard) async throws(CoreError) -> CardOptions {
        if let options = cardOptions[card.homeDeckID] { return options }
        let deck = try await store.core.getDeck(.with { $0.did = card.homeDeckID })
        let config = try await store.core.getDeckConfig(.with { $0.dcid = deck.normal.configID }).config
        let seconds = config.capAnswerTimeToSecs
        let answerAction: ReviewerCommand? = switch config.answerAction {
        case .answerAgain: .rateAgain
        case .answerHard: .rateHard
        case .answerGood: .rateGood
        case .showReminder: nil
        default: .buryCard
        }
        let options = CardOptions(
            answerTimeCap: .seconds(seconds > 0 ? Int(seconds) : 60),
            deckName: deck.name.replacingOccurrences(of: "\u{1F}", with: "::"),
            showsAnswerTimer: config.showTimer,
            stopsTimerOnAnswer: config.stopTimerOnAnswer,
            questionDelay: Self.autoAdvanceDelay(config.secondsToShowQuestion),
            answerDelay: Self.autoAdvanceDelay(config.secondsToShowAnswer),
            waitForAudio: config.waitForAudio,
            questionAction: config.questionAction == .showReminder ? nil : .showAnswer,
            answerAction: answerAction,
            audio: AudioOptions(
                autoplay: !config.disableAutoplay,
                replaysQuestionOnAnswer: !config.skipQuestionWhenReplayingAnswer
            )
        )
        cardOptions[card.homeDeckID] = options
        return options
    }

    private static func autoAdvanceDelay(_ seconds: Float) -> Duration {
        guard seconds.isFinite, seconds > 0 else { return .zero }
        return .milliseconds(Int64(min(9999, seconds) * 1000))
    }

    // MARK: Audio

    /// The collection's media folder, which cards' images, sounds and fonts
    /// come from.
    public var mediaFolder: URL {
        store.location.mediaFolder
    }

    /// What plays by itself when the shown side appears: the side's audio in
    /// order, unless the deck's options turn automatic playing off.
    public func soundsToAutoplay() -> [CardSound] {
        guard let card = state.card, audioOptions.autoplay else { return [] }
        return sounds(state.answer == nil ? card.question.audio : card.answer.audio)
    }

    /// What replaying the shown side plays: on the question side its audio;
    /// on the answer side the answer's audio, after the question's unless
    /// the deck's options skip the question.
    public func soundsToReplay() -> [CardSound] {
        guard let card = state.card else { return [] }
        if state.answer == nil {
            return sounds(card.question.audio)
        }
        return sounds((audioOptions.replaysQuestionOnAnswer ? card.question.audio : []) + card.answer.audio)
    }

    /// The sound behind one of the card's replay buttons, by the button's
    /// `data-play` id such as `q:0` or `a:1`.
    public func sound(forPlayButton id: String) -> CardSound? {
        guard let card = state.card, let (isQuestion, index) = PlayButtons.parse(id) else { return nil }
        let audio = isQuestion ? card.question.audio : card.answer.audio
        return audio.indices.contains(index) ? CardSound(audio[index], mediaFolder: store.location.mediaFolder) : nil
    }

    private func sounds(_ tags: [Anki_CardRendering_AVTag]) -> [CardSound] {
        tags.map { CardSound($0, mediaFolder: store.location.mediaFolder) }
    }
}

/// The deck options that studying a card follows.
private struct CardOptions {
    var answerTimeCap: Duration
    var deckName: String
    var showsAnswerTimer: Bool
    var stopsTimerOnAnswer: Bool
    var questionDelay: Duration
    var answerDelay: Duration
    var waitForAudio: Bool
    var questionAction: ReviewerCommand?
    var answerAction: ReviewerCommand?
    var audio: AudioOptions
}

public struct AutoAdvancePlan: Equatable, Sendable {
    public let delay: Duration
    public let waitForAudio: Bool
    /// A nil command shows the time-elapsed reminder.
    public let command: ReviewerCommand?
}

public struct StudyTimebox: Equatable, Sendable {
    public let reviewed: Int
    public let limit: Duration
}

extension String {
    /// The core's text wraps each number in Unicode isolation marks, which
    /// are of no use in a single-language line.
    var withoutIsolationMarks: String {
        filter { $0 != "\u{2068}" && $0 != "\u{2069}" }
    }
}
