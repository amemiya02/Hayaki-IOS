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
    /// text-to-speech) are replaced by the core with `[anki:play:q:0]` style
    /// markers, numbered in the order of `audio`.
    public let html: String
    /// The side's audio and video, in the order they play.
    public let audio: [Anki_CardRendering_AVTag]
}

/// The card being studied: both sides as the core renders them, and what
/// each rating would do to it.
public struct StudyCard: Equatable, Sendable {
    public let id: Int64
    public let noteID: Int64
    /// The deck the card belongs to, whose options apply to it.
    public let homeDeckID: Int64
    public let question: CardSide
    public let answer: CardSide
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
        // A full render: rendering stops early only for the filters desktop
        // Anki's Python code adds, which Hayaki does not have.
        let rendered = try await core.renderExistingCard(.with {
            $0.cardID = card.id
            $0.browser = false
            $0.partialRender = false
        })
        return StudyCard(
            id: card.id,
            noteID: card.noteID,
            homeDeckID: card.originalDeckID != 0 ? card.originalDeckID : card.deckID,
            question: try await side(rendered.questionNodes, isQuestion: true, core: core),
            answer: try await side(rendered.answerNodes, isQuestion: false, core: core),
            css: rendered.css,
            bodyClass: "card card\(card.templateIdx + 1)",
            intervals: intervals,
            states: states
        )
    }

    private static func side(
        _ nodes: [Anki_CardRendering_RenderedTemplateNode],
        isQuestion: Bool,
        core: CoreClient
    ) async throws(CoreError) -> CardSide {
        let html = nodes.map { node in
            switch node.value {
            case .text(let text): text
            // Only left by a partial render, which this is not; the
            // field's text is the best that can be shown.
            case .replacement(let replacement): replacement.currentText
            case nil: ""
            }
        }.joined()
        let extracted = try await core.extractAvTags(.with {
            $0.text = html
            $0.questionSide = isQuestion
        })
        return CardSide(html: extracted.text, audio: extracted.avTags)
    }
}
