import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Observation

/// One deck in the deck list, with today's counts and its child decks.
public struct DeckNode: Identifiable, Equatable, Sendable {
    public let id: Int64
    /// The deck's own name, without its parents' names.
    public let name: String
    /// The deck's name with its parents' names, as Anki stores it, such as
    /// "Languages::Japanese".
    public let fullName: String
    public let counts: DeckCounts
    /// Whether the learner collapsed this deck, hiding its child decks.
    public internal(set) var isCollapsed: Bool
    /// Whether this is a filtered deck, which borrows cards from other decks.
    public let isFiltered: Bool
    public internal(set) var children: [DeckNode]
    /// All cards in the deck and its child decks, whatever their state.
    public let totalCards: Int

    init(_ node: Anki_Decks_DeckTreeNode, parentName: String? = nil) {
        id = node.deckID
        name = node.name
        fullName = parentName.map { "\($0)::\(node.name)" } ?? node.name
        counts = DeckCounts(
            new: Int(node.newCount),
            learning: Int(node.learnCount),
            due: Int(node.reviewCount)
        )
        isCollapsed = node.collapsed
        isFiltered = node.filtered
        children = node.children.map { [fullName] child in DeckNode(child, parentName: fullName) }
        totalCards = Int(node.totalIncludingChildren)
    }
}

/// How many cards of a deck, including its child decks, can be studied today,
/// as the core reports them after applying the deck's daily limits.
public struct DeckCounts: Equatable, Sendable {
    public let new: Int
    public let learning: Int
    public let due: Int

    public var isEmpty: Bool { new == 0 && learning == 0 && due == 0 }
}

/// The deck list: every deck as a nested list with today's counts.
@MainActor
@Observable
public final class DeckListModel {
    public enum State: Equatable {
        case loading
        case loaded
        case failed(message: String)
    }

    public private(set) var state: State = .loading
    public internal(set) var decks: [DeckNode] = []

    /// Whether the collection has no cards at all, as on first launch, so
    /// the screen offers to import a package instead of an empty deck list.
    public var hasNoCards: Bool {
        state == .loaded && decks.allSatisfy { $0.totalCards == 0 }
    }

    @ObservationIgnored let store: CollectionStore

    /// Changes after which the decks or their counts may differ.
    private static let relevantChanges: CollectionChange = [.deck, .card, .config, .deckConfig, .studyQueues]

    public init(store: CollectionStore) {
        self.store = store
    }

    /// Reads the deck list and today's counts from the core.
    public func refresh() async {
        do {
            // Counts are only computed when the request says what "now" is.
            let root = try await store.core.deckTree(.with { $0.now = Int64(Date().timeIntervalSince1970) })
            decks = root.children.map { DeckNode($0) }
            state = .loaded
        } catch {
            state = .failed(message: error.message)
        }
    }

    /// Shows the deck list, then keeps it current whenever the collection
    /// changes in a way that could alter it, until the calling task is
    /// cancelled. The deck list screen runs this in its `.task`.
    public func run() async {
        // Subscribed before reading, so no change in between is missed. A new
        // subscription each time: SwiftUI cancels and restarts the task when
        // the screen disappears and reappears, and cancelling ends a stream.
        let changes = store.changes()
        await refresh()
        for await change in changes where !change.isDisjoint(with: Self.relevantChanges) {
            await refresh()
        }
    }
}
