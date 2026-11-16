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

/// A deck offered as a place to put another deck.
public struct DeckChoice: Identifiable, Equatable, Sendable {
    public let id: DeckNode.ID
    public let name: String
    public let fullName: String
    /// 0 for a top-level deck, 1 for a deck inside it, and so on.
    public let depth: Int
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
        let fullName = try available(fullName(of: name, inside: parentID))
        var deck = try await store.core.newDeck()
        deck.name = fullName
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
        let newName = try available(fullName(of: name, inside: parentID(of: id)), for: id)
        try await store.modify(.renameDeck(.with {
            $0.deckID = id
            $0.newName = newName
        }))
        await refresh()
    }

    /// What deleting a deck would take with it, to state before the learner
    /// confirms.
    public func deletion(of id: DeckNode.ID) async throws(CoreError) -> DeckDeletion {
        guard let deck = deck(id) else {
            return DeckDeletion(cardCount: 0, subdeckCount: 0, isFiltered: false)
        }
        func subdecks(of deck: DeckNode) -> [DeckNode] {
            deck.children.flatMap { [$0] + subdecks(of: $0) }
        }
        let all = [deck] + subdecks(of: deck)
        // The core deletes the cards of the normal decks among them, wherever
        // a filtered deck has borrowed them to; the cards in filtered decks go
        // back to their own decks. `did:` matches exactly those: cards in the
        // listed decks (not their children) or borrowed from them.
        let normal = all.filter { !$0.isFiltered }.map { String($0.id) }
        let cardCount = normal.isEmpty ? 0 : try await store.core.searchCards(.with {
            $0.search = "did:\(normal.joined(separator: ","))"
        }).ids.count
        return DeckDeletion(cardCount: cardCount, subdeckCount: all.count - 1, isFiltered: deck.isFiltered)
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

    /// Moves a deck, with its child decks and cards, under another deck, or
    /// to the top level when `parentID` is nil. The deck it goes into is
    /// expanded so the learner sees it there.
    public func moveDeck(_ id: DeckNode.ID, under parentID: DeckNode.ID?) async throws(CoreError) {
        if let deck = deck(id) {
            try available(fullName(of: deck.name, inside: parentID), for: id)
        }
        try await store.modify(.reparentDecks(.with {
            $0.deckIds = [id]
            // The core reads 0 as the top level.
            $0.newParent = parentID ?? 0
        }))
        await refresh()
        try await expandAncestors(of: id)
    }

    /// The decks a deck can be put inside, in list order, each with how deep
    /// it sits. Filtered decks cannot hold other decks, and a deck cannot go
    /// inside itself or its own child decks, so with `excludedID` that deck
    /// and everything below it are left out.
    public func parentChoices(excludingSubtreeOf excludedID: DeckNode.ID? = nil) -> [DeckChoice] {
        func choices(_ decks: [DeckNode], depth: Int) -> [DeckChoice] {
            decks.flatMap { deck -> [DeckChoice] in
                guard deck.id != excludedID, !deck.isFiltered else { return [] }
                let choice = DeckChoice(id: deck.id, name: deck.name, fullName: deck.fullName, depth: depth)
                return [choice] + choices(deck.children, depth: depth + 1)
            }
        }
        return choices(decks, depth: 0)
    }

    /// The deck a deck sits in; nil at the top level.
    public func parentID(of id: DeckNode.ID) -> DeckNode.ID? {
        path(to: id)?.dropLast().last?.id
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

    /// Whether a name the learner typed is empty or only spaces.
    public static func isBlank(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A deck's full name when it is called `name` and sits inside `parentID`.
    private func fullName(of name: String, inside parentID: DeckNode.ID?) -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parentID, let parent = deck(parentID) else { return name }
        return "\(parent.fullName)::\(name)"
    }

    /// Returns `fullName` if a deck (the deck `id`, when renaming or moving
    /// it) can take it. The core would quietly add "+" to a name that is
    /// taken and call a blank deck "blank", so both are refused here with a
    /// message the learner can act on.
    @discardableResult
    private func available(_ fullName: String, for id: DeckNode.ID? = nil) throws(CoreError) -> String {
        let leafName = fullName.components(separatedBy: "::").last ?? fullName
        if Self.isBlank(leafName) {
            throw CoreError(
                kind: .invalidInput,
                message: String(localized: "Enter a name for the deck.", bundle: .module)
            )
        }
        // Anki compares deck names ignoring case.
        if let existing = deck(fullName: fullName), existing.id != id {
            throw CoreError(
                kind: .exists,
                message: String(localized: "There is already a deck named “\(leafName)” there.", bundle: .module)
            )
        }
        return fullName
    }

    /// The deck with this full name, ignoring letter case.
    private func deck(fullName: String) -> DeckNode? {
        func search(_ decks: [DeckNode]) -> DeckNode? {
            for deck in decks {
                if deck.fullName.caseInsensitiveCompare(fullName) == .orderedSame { return deck }
                if let found = search(deck.children) { return found }
            }
            return nil
        }
        return search(decks)
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
