import AnkiCore
import AnkiProto
import CollectionStore
import Foundation

/// What deleting a deck takes with it.
public struct DeckDeletion: Equatable, Sendable {
    /// The cards deleted with the deck, including those of its child decks.
    public let cardCount: Int
    /// The child decks deleted with it, at every level below it.
    public let subdeckCount: Int
    /// A filtered deck deletes no cards: they go back to their own decks.
    public let isFiltered: Bool

    public init(cardCount: Int, subdeckCount: Int, isFiltered: Bool) {
        self.cardCount = cardCount
        self.subdeckCount = subdeckCount
        self.isFiltered = isFiltered
    }
}

/// Organising decks: creating, renaming, deleting, moving, and collapsing or
/// expanding parent decks. Each action goes through the core, then shows the
/// deck list as it now is.
extension DeckListModel {
    /// Creates a deck called `name`, at the top level or inside `parentID`,
    /// and returns its id. The decks it sits in are expanded so it can be
    /// seen.
    @discardableResult
    public func createDeck(named name: String, inside parentID: DeckNode.ID?) async throws(CoreError) -> DeckNode.ID {
        var deck = try await store.core.newDeck()
        deck.name = fullName(of: name, inside: parentID)
        // The core makes new decks collapsed; a new deck has nothing to hide.
        deck.common.studyCollapsed = false
        let id = try await store.modify(.addDeck(deck)).id
        await refresh()
        try await expandAncestors(of: id)
        return id
    }

    /// Gives a deck a new name; it stays where it is, with its child decks
    /// and cards.
    public func renameDeck(_ id: DeckNode.ID, to name: String) async throws(CoreError) {
        let parentID = path(to: id)?.dropLast().last?.id
        try await store.modify(.renameDeck(.with {
            $0.deckID = id
            $0.newName = fullName(of: name, inside: parentID)
        }))
        await refresh()
    }

    /// What deleting a deck would take with it, to state before the learner
    /// confirms.
    public func deletion(of id: DeckNode.ID) -> DeckDeletion {
        guard let deck = deck(id) else {
            return DeckDeletion(cardCount: 0, subdeckCount: 0, isFiltered: false)
        }
        func subdecks(of deck: DeckNode) -> [DeckNode] {
            deck.children.flatMap { [$0] + subdecks(of: $0) }
        }
        let all = [deck] + subdecks(of: deck)
        return DeckDeletion(
            // The cards of filtered decks go back to their own decks.
            cardCount: all.filter { !$0.isFiltered }.map(\.cardsInDeck).reduce(0, +),
            subdeckCount: all.count - 1,
            isFiltered: deck.isFiltered
        )
    }

    /// Deletes a deck with its child decks and their cards, and returns how
    /// many cards were deleted. Deleting a filtered deck returns its cards to
    /// their own decks.
    @discardableResult
    public func deleteDeck(_ id: DeckNode.ID) async throws(CoreError) -> Int {
        let response = try await store.modify(.removeDecks(.with { $0.dids = [id] }))
        await refresh()
        return Int(response.count)
    }

    /// Collapses or expands a parent deck, hiding or showing its child decks.
    /// The deck list shows it at once; the core keeps it for next time.
    public func setCollapsed(_ collapsed: Bool, deck id: DeckNode.ID) async throws(CoreError) {
        decks = Self.updating(id, in: decks) { $0.isCollapsed = collapsed }
        do {
            try await store.modify(.setDeckCollapsed(.with {
                $0.deckID = id
                $0.collapsed = collapsed
                $0.scope = .reviewer
            }))
        } catch {
            await refresh()
            throw error
        }
    }

    /// Whether the learner has decks of their own, beyond an empty Default
    /// deck. A collection with decks but no cards is shown as a deck list,
    /// so a deck the learner just created appears.
    public var hasOwnDecks: Bool {
        decks.contains { $0.id != Self.defaultDeckID || !$0.children.isEmpty || $0.totalCards > 0 }
    }

    /// The id of the Default deck every collection has.
    static let defaultDeckID: DeckNode.ID = 1

    // MARK: Looking up decks

    /// The deck with this id, wherever it is in the tree.
    func deck(_ id: DeckNode.ID) -> DeckNode? {
        path(to: id)?.last
    }

    /// The decks from the top level down to the deck with this id.
    func path(to id: DeckNode.ID) -> [DeckNode]? {
        func search(_ decks: [DeckNode]) -> [DeckNode]? {
            for deck in decks {
                if deck.id == id { return [deck] }
                if let below = search(deck.children) { return [deck] + below }
            }
            return nil
        }
        return search(decks)
    }

    /// A deck's full name when it is called `name` and sits inside `parentID`.
    private func fullName(of name: String, inside parentID: DeckNode.ID?) -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parentID, let parent = deck(parentID) else { return name }
        return "\(parent.fullName)::\(name)"
    }

    /// Expands every collapsed deck above the deck with this id.
    private func expandAncestors(of id: DeckNode.ID) async throws(CoreError) {
        for ancestor in path(to: id)?.dropLast() ?? [] where ancestor.isCollapsed {
            try await setCollapsed(false, deck: ancestor.id)
        }
    }

    /// `decks` with the deck of this id changed by `change`.
    private static func updating(_ id: DeckNode.ID, in decks: [DeckNode], _ change: (inout DeckNode) -> Void) -> [DeckNode] {
        decks.map { deck in
            var deck = deck
            if deck.id == id {
                change(&deck)
            } else {
                deck.children = updating(id, in: deck.children, change)
            }
            return deck
        }
    }
}
