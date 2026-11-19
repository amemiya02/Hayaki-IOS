import AnkiCore
import AnkiProto

/// A common search the learner can reach without typing Anki's search
/// syntax. Applying one puts its search, in that syntax, in the search field.
public enum QuickFilter: Hashable, Sendable {
    /// The cards of a deck, by its full name, and of its subdecks.
    case deck(String)
    /// The cards whose note has a tag (or one of its child tags).
    case tag(String)
    /// The cards with a flag.
    case flag(CardRow.Flag)
    case anyFlag
    case noFlag
    case noteType(String)
    case new
    case learning
    case review
    case buried
    case marked
    /// The suspended cards.
    case suspended
    /// The cards waiting to be reviewed today, overdue ones included: what
    /// Anki's `is:due` finds.
    case dueToday

    enum Category: CaseIterable {
        case deck, tag, noteType, flag, state
    }

    var category: Category {
        switch self {
        case .deck: .deck
        case .tag: .tag
        case .noteType: .noteType
        case .flag, .anyFlag, .noFlag: .flag
        case .new, .learning, .review, .buried, .marked, .suspended, .dueToday: .state
        }
    }

    /// The filter as a node the core turns into search text, quoting and
    /// escaping names as its syntax needs.
    var searchNode: Anki_Search_SearchNode {
        .with {
            switch self {
            case .deck(let name): $0.deck = name
            case .tag(let name): $0.tag = name
            case .flag(let flag): $0.flag = flag.searchFlag
            case .anyFlag: $0.flag = .any
            case .noFlag: $0.flag = .none
            case .noteType(let name): $0.note = name
            case .new: $0.cardState = .new
            case .learning: $0.cardState = .learn
            case .review: $0.cardState = .review
            case .buried: $0.cardState = .buried
            case .marked: $0.tag = "marked"
            case .suspended: $0.cardState = .suspended
            case .dueToday: $0.cardState = .due
            }
        }
    }
}

/// What the browser offers to choose from: the decks and tags for the quick
/// filters, and the decks cards can be moved to.
public struct BrowserChoices: Equatable, Sendable {
    /// Full deck names, such as "Spanish::Verbs", filtered decks included,
    /// in the core's order.
    public var decks: [String] = []
    /// Tags, sorted as the core sorts them.
    public var tags: [String] = []
    public var noteTypes: [String] = []
    /// The decks cards can be moved to: every deck except filtered decks,
    /// which only borrow cards.
    public var moveDestinations: [DeckChoice] = []

    public init(decks: [String] = [], tags: [String] = [], noteTypes: [String] = [], moveDestinations: [DeckChoice] = []) {
        self.decks = decks
        self.tags = tags
        self.noteTypes = noteTypes
        self.moveDestinations = moveDestinations
    }
}

/// A deck the learner can pick, by id and full name.
public struct DeckChoice: Identifiable, Hashable, Sendable {
    public let id: Int64
    /// The full name, such as "Spanish::Verbs".
    public let name: String

    public init(id: Int64, name: String) {
        self.id = id
        self.name = name
    }
}

extension CardRow.Flag {
    var searchFlag: Anki_Search_SearchNode.Flag {
        switch self {
        case .red: .red
        case .orange: .orange
        case .green: .green
        case .blue: .blue
        case .pink: .pink
        case .turquoise: .turquoise
        case .purple: .purple
        }
    }
}
