import AnkiCore
import AnkiProto
import Foundation

/// How many cards of the deck being studied are left today, as the core
/// counts them after the deck's daily limits.
public struct StudyCounts: Equatable, Sendable {
    public let new: Int
    public let learning: Int
    public let due: Int

    public init(new: Int, learning: Int, due: Int) {
        self.new = new
        self.learning = learning
        self.due = due
    }

    init(_ queued: Anki_Scheduler_QueuedCards) {
        new = Int(queued.newCount)
        learning = Int(queued.learningCount)
        due = Int(queued.reviewCount)
    }
}

/// The learner's judgement of a review.
public enum Rating: CaseIterable, Sendable, Hashable {
    case again
    case hard
    case good
    case easy

    var proto: Anki_Scheduler_CardAnswer.Rating {
        switch self {
        case .again: .again
        case .hard: .hard
        case .good: .good
        case .easy: .easy
        }
    }
}

/// The interval each rating would give the card, as the core describes it in
/// the core's language, such as "10m" or "4d".
public struct RatingIntervals: Equatable, Sendable {
    private let labels: [String]

    init(_ described: [String]) {
        labels = described.map(\.withoutIsolationMarks)
    }

    public subscript(rating: Rating) -> String {
        let index = Rating.allCases.firstIndex(of: rating)!
        return index < labels.count ? labels[index] : ""
    }
}

/// One side of a card, as the core renders it from the card template.
public struct CardSide: Equatable, Sendable {
    /// The side's HTML. Audio and video references (`[sound:…]` and
    /// text-to-speech) are replaced by replay buttons,
    /// `<a class="replay-button" data-play="q:0">` style, numbered per side in
    /// the order of the side's `audio`. On the answer side, `{{FrontSide}}`
    /// brings the question's buttons (`q:…`) along.
    public let html: String
    /// The side's audio and video, in the order they play.
    public let audio: [Anki_CardRendering_AVTag]
}

/// The card being studied: both sides as the core renders them, and what
/// each rating would do to it.
public struct StudyCard: Equatable, Sendable {
    public let id: Int64
    public let noteID: Int64
    public let flag: UInt32
    public let isNoteMarked: Bool
    /// The deck the card belongs to, whose options apply to it.
    public let homeDeckID: Int64
    /// The question side. On a card that asks the learner to type the
    /// answer, it has a text field (`<input id=typeans>`).
    public let question: CardSide
    /// The answer side. On a card that asks the learner to type the answer,
    /// it shows the core's comparison of what was typed with the expected
    /// answer (`<code id=typeans>`).
    public private(set) var answer: CardSide
    /// The note type's styling.
    public let css: String
    /// The classes Anki puts on the card's `<body>`: `card card1` for the
    /// first card template, `card card2` for the second, and so on.
    public let bodyClass: String
    /// The interval each rating would give.
    public let intervals: RatingIntervals
    /// The card's scheduling now and after each rating, from the core,
    /// which answering hands back to the core.
    let states: Anki_Scheduler_SchedulingStates
    /// What a card that asks for typing expects; nil for other cards.
    let typedAnswerPrompt: TypedAnswerPrompt?
    /// The answer side before the comparison goes in.
    let answerBeforeTyping: String

    /// Whether the card asks the learner to type the answer before showing
    /// it.
    public var asksForTypedAnswer: Bool {
        typedAnswerPrompt != nil
    }

    static func isMarkTag(_ tag: String) -> Bool {
        tag.caseInsensitiveCompare("marked") == .orderedSame
    }

    /// Renders a card the core's queue handed out.
    static func render(_ queued: Anki_Scheduler_QueuedCards.QueuedCard, core: CoreClient) async throws(CoreError) -> StudyCard {
        try await render(
            queued.card,
            states: queued.states,
            intervals: RatingIntervals(try await core.describeNextStates(queued.states).vals),
            core: core
        )
    }

    /// The same card rendered again from its note as it is now, after the
    /// note or its note type changed. Its scheduling is unchanged.
    func redrawn(core: CoreClient) async throws(CoreError) -> StudyCard {
        try await Self.render(
            try await core.getCard(.with { $0.cid = id }),
            states: states,
            intervals: intervals,
            core: core
        )
    }

    private static func render(
        _ card: Anki_Cards_Card,
        states: Anki_Scheduler_SchedulingStates,
        intervals: RatingIntervals,
        core: CoreClient
    ) async throws(CoreError) -> StudyCard {
        // A partial render, as desktop Anki makes: the core leaves
        // {{FrontSide}} for us to fill with the question as shown, its audio
        // already turned into question markers, so the answer side does not
        // play the question's audio again; and fields with filters the core
        // does not know (add-on filters on desktop) keep their text.
        let rendered = try await core.renderExistingCard(.with {
            $0.cardID = card.id
            $0.browser = false
            $0.partialRender = true
        })
        let question = try await side(rendered.questionNodes, frontSide: "", isQuestion: true, core: core)
        let answer = try await side(rendered.answerNodes, frontSide: question.withMarkers, isQuestion: false, core: core)
        let typing = try await TypedAnswerPrompt.questionSide(question.side.html, card: card, core: core)
        let note = try await core.getNote(.with { $0.nid = card.noteID })
        return StudyCard(
            id: card.id,
            noteID: card.noteID,
            flag: card.flags & 7,
            isNoteMarked: note.tags.contains(where: Self.isMarkTag),
            homeDeckID: card.originalDeckID != 0 ? card.originalDeckID : card.deckID,
            question: CardSide(html: typing.html, audio: question.side.audio),
            // Until the learner types something, the comparison shows the
            // expected answer, as in Anki.
            answer: CardSide(
                html: try await TypedAnswerPrompt.answerSide(answer.side.html, prompt: typing.prompt, typed: "", core: core),
                audio: answer.side.audio
            ),
            css: rendered.css,
            bodyClass: "card card\(card.templateIdx + 1)",
            intervals: intervals,
            states: states,
            typedAnswerPrompt: typing.prompt,
            answerBeforeTyping: answer.side.html
        )
    }

    /// The card with its answer side showing the core's comparison of
    /// `typed` with the expected answer, for a card that asks for typing.
    /// Any other card comes back unchanged.
    func answering(typed: String, core: CoreClient) async throws(CoreError) -> StudyCard {
        guard let typedAnswerPrompt else { return self }
        var card = self
        card.answer = CardSide(
            html: try await TypedAnswerPrompt.answerSide(answerBeforeTyping, prompt: typedAnswerPrompt, typed: typed, core: core),
            audio: answer.audio
        )
        return card
    }

    /// One side's HTML, with its audio taken out by the core. `withMarkers`
    /// is the HTML before the replay buttons go in, for `{{FrontSide}}`.
    private static func side(
        _ nodes: [Anki_CardRendering_RenderedTemplateNode],
        frontSide: String,
        isQuestion: Bool,
        core: CoreClient
    ) async throws(CoreError) -> (side: CardSide, withMarkers: String) {
        let html = nodes.map { node in
            switch node.value {
            case .text(let text): text
            case .replacement(let replacement):
                replacement.fieldName == "FrontSide" ? frontSide : replacement.currentText
            case nil: ""
            }
        }.joined()
        let extracted = try await core.extractAvTags(.with {
            $0.text = html
            $0.questionSide = isQuestion
        })
        let shown = PlayButtons.insert(
            into: extracted.text,
            label: String(localized: "Play Audio", bundle: .module, comment: "VoiceOver label of the replay button on a card.")
        )
        return (CardSide(html: shown, audio: extracted.avTags), extracted.text)
    }
}
