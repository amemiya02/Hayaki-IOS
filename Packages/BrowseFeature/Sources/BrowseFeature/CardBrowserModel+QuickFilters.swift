import AnkiCore
import AnkiProto
import CollectionStore

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
            choices = BrowserChoices(
                decks: allDecks.entries.map(\.name),
                tags: tags.vals,
                moveDestinations: normalDecks.entries.map { DeckChoice(id: $0.id, name: $0.name) }
            )
        } catch {
            // The menus stay as they were; the next change loads them again.
        }
    }
}
