import AnkiCore
import AnkiProto
import CollectionStore
import Foundation

extension CardBrowserModel {
    /// Searches with a quick filter instead of the current search. The search
    /// field then shows the filter's search in Anki's syntax, which the
    /// learner can refine.
    public func applyFilter(_ filter: QuickFilter) async {
        do {
            searchText = try await store.core.buildSearchString(filter.searchNode).val
        } catch {
            failure = error.message
            return
        }
        await search()
    }

    /// The search text and active filters shown when reopening the filter picker.
    public var filterDraft: (query: String, filters: [QuickFilter]) {
        if let filterSelection, filterSelection.builtQuery == searchText {
            return (filterSelection.query, filterSelection.filters)
        }
        return (searchText, [])
    }

    /// Joins choices within one category with OR, and joins categories and
    /// the typed query with AND. The core normalizes and escapes the expression.
    public func applyFilters(_ filters: [QuickFilter], query: String? = nil) async {
        let query = (query ?? filterDraft.query).trimmingCharacters(in: .whitespacesAndNewlines)
        let groups = Dictionary(grouping: filters, by: \.category)
        var nodes = QuickFilter.Category.allCases.compactMap { category -> Anki_Search_SearchNode? in
            guard let choices = groups[category], let first = choices.first else { return nil }
            if choices.count == 1 { return first.searchNode }
            return .with { $0.group = .with {
                $0.joiner = .or
                $0.nodes = choices.map(\.searchNode)
            } }
        }
        if !query.isEmpty {
            nodes.insert(.with { $0.parsableText = query }, at: 0)
        }
        do {
            let builtQuery = nodes.isEmpty ? "" : try await store.core.buildSearchString(.with {
                $0.group = .with { $0.nodes = nodes }
            }).val
            filterSelection = (query, filters, builtQuery)
            searchText = builtQuery
            failure = nil
        } catch {
            failure = error.message
            return
        }
        await search()
    }

    /// Loads the decks and tags the quick filters and the Move action offer.
    /// `run()` loads them too, and again when decks or tags change.
    public func loadChoices() async {
        do {
            // An empty Default deck is hidden, as in the deck list.
            let allDecks = try await store.core.getDeckNames(.with {
                $0.skipEmptyDefault = true
                $0.includeFiltered = true
            })
            let normalDecks = try await store.core.getDeckNames(.with {
                $0.skipEmptyDefault = true
                $0.includeFiltered = false
            })
            let tags = try await store.core.allTags()
            let noteTypes = try await store.core.getNotetypeNames()
            choices = BrowserChoices(
                decks: allDecks.entries.map(\.name),
                tags: tags.vals,
                noteTypes: noteTypes.entries.map(\.name),
                moveDestinations: normalDecks.entries.map { DeckChoice(id: $0.id, name: $0.name) }
            )
        } catch {
            // The menus stay as they were; the next change loads them again.
        }
    }
}
