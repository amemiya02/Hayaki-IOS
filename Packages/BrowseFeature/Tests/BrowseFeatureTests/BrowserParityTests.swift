import BrowseFeature
import CollectionStore
import CollectionTesting
import DecksFeature
import Foundation
import Testing

@MainActor
@Suite("Browse parity")
struct BrowserParityTests {
    @Test("Notes mode shows one row per note and keeps the query when changing modes")
    func notesMode() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Geography")
            try await store.addNotes(ofType: "Basic (and reversed card)", fields: [
                ["Alpha", "A"],
                ["Beta", "B"],
            ], toDeck: deck)
            let model = CardBrowserModel(store: store)
            model.searchText = "deck:Geography"
            await model.search()
            #expect(model.rowIDs.count == 4)
            model.selectAll()

            await model.setMode(.notes)
            #expect(model.searchedText == "deck:Geography")
            #expect(model.rowIDs.count == 2)
            #expect(model.selection.isEmpty)
            let first = try #require(model.rowIDs.first)
            await model.loadRow(first)
            #expect(model.row(for: first)?.cells["noteFld"] == "Alpha")
            #expect(model.sortColumns.contains { $0.id == "noteFld" })

            await model.setMode(.cards)
            #expect(model.rowIDs.count == 4)
            #expect(model.searchedText == "deck:Geography")
        }
    }
}

extension BrowserParityTests {
    @Test("Visible columns and sort order are independent per mode and survive reopening Browse")
    func columnsAndSort() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Languages")
            try await store.addBasicCard(front: "alpha", back: "First answer", inDeck: deck, tags: ["language"])
            try await store.addBasicCard(front: "beta", back: "Second answer", inDeck: deck)
            let model = CardBrowserModel(store: store)
            await model.search()
            #expect(model.visibleColumnIDs == ["noteFld", "template", "cardDue", "deck"])
            await model.setColumns(["answer", "noteFld"])
            await model.setSort(CardSort(column: "noteFld", reverse: true))
            let first = try #require(model.rowIDs.first)
            await model.loadRow(first)
            let row = try #require(model.row(for: first))
            #expect(row.cells["answer"] == "Second answer")
            #expect(row.cells["noteFld"] == "beta")
            // The row also carries the deck and due date it always shows.
            #expect(row.deck == "Languages")

            await model.setMode(.notes)
            #expect(model.visibleColumnIDs == ["noteFld", "note", "template", "noteTags"])
            #expect(model.sort == .default)
            await model.setColumns(["noteTags", "noteFld"])
            await model.setColumns([])
            #expect(model.visibleColumnIDs == ["noteTags", "noteFld"])

            let reopened = CardBrowserModel(store: store)
            await reopened.search()
            #expect(reopened.mode == .notes)
            #expect(reopened.visibleColumnIDs == ["noteTags", "noteFld"])

            await reopened.setMode(.cards)
            #expect(reopened.visibleColumnIDs == ["answer", "noteFld"])
            #expect(reopened.sort == CardSort(column: "noteFld", reverse: true))
        }
    }
}

extension BrowserParityTests {
    @Test("Saved searches keep the submitted query in shared collection settings")
    func savedSearches() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish Verbs")
            let card = try await store.addBasicCard(front: "correr", back: "run", inDeck: deck)
            let model = CardBrowserModel(store: store)
            await model.applyFilter(.deck("Spanish Verbs"))
            let query = model.searchedText
            model.searchText = "unsubmitted draft"
            await model.saveSearch(named: "Verbs")
            await model.saveSearch(named: "Verbs")

            let reopened = CardBrowserModel(store: store)
            await reopened.loadSavedSearches()
            #expect(reopened.savedSearches.map(\.name) == ["Verbs"])
            #expect(reopened.savedSearches.map(\.query) == [query])
            await reopened.openSavedSearch(try #require(reopened.savedSearches.first))
            #expect(reopened.rowIDs == [card])
            #expect(reopened.searchText == query)

            await reopened.removeSavedSearch(named: "Verbs")
            await model.loadSavedSearches()
            #expect(model.savedSearches.isEmpty)
        }
    }
}

extension BrowserParityTests {
    @Test("Combining filter choices matches any selection within a category and every selected category")
    func combiningFilters() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish Verbs")
            let french = try await store.addDeck(named: "French")
            let japanese = try await store.addDeck(named: "Japanese")
            let correr = try await store.addBasicCard(front: "correr", back: "run", inDeck: spanish, tags: ["verb"])
            let courir = try await store.addBasicCard(front: "courir", back: "run", inDeck: french, tags: ["verb"])
            try await store.addBasicCard(front: "rojo", back: "red", inDeck: spanish, tags: ["adjective"])
            try await store.addBasicCard(front: "hashiru", back: "run", inDeck: japanese, tags: ["verb"])
            let model = CardBrowserModel(store: store)
            model.searchText = "back:run"
            await model.search()
            await model.applyFilters([.deck("Spanish Verbs"), .deck("French"), .tag("verb"), .new, .noteType("Basic")])
            #expect(Set(model.rowIDs) == [correr, courir])
            #expect(model.filterDraft.query == "back:run")
            #expect(model.filterDraft.filters.count == 5)
            await model.applyFilters([])
            #expect(model.searchedText == "back:run")
            #expect(model.rowIDs.count == 3)
        }
    }
}

extension BrowserParityTests {
    @Test("Selecting notes across pages applies card actions to siblings and undo restores the query")
    func notesBulkActions() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Languages")
            let fields = (0...CardBrowserModel.pageSize).map { ["term \($0)", "answer \($0)"] }
            try await store.addNotes(ofType: "Basic (and reversed card)", fields: fields, toDeck: deck)
            let model = CardBrowserModel(store: store)
            model.searchText = "deck:Languages"
            await model.setMode(.notes)
            let first = try #require(model.rowIDs.first)
            let last = try #require(model.rowIDs.last)
            await model.loadRow(first)
            model.selection.insert(first)
            await model.loadRow(last)
            model.selection.insert(last)

            await model.perform(.flag(.blue))
            #expect(try await store.cardCount(matching: "flag:4") == 4)
            #expect(await model.undoLastAction())
            #expect(try await store.cardCount(matching: "flag:4") == 0)
            #expect(model.searchedText == "deck:Languages")
            #expect(model.selection == [first, last])

            await model.perform(.toggleMark)
            #expect(try await store.cardCount(matching: "tag:marked") == 4)
            await model.perform(.toggleMark)
            #expect(try await store.cardCount(matching: "tag:marked") == 0)
            #expect(await model.undoLastAction())
            #expect(try await store.cardCount(matching: "tag:marked") == 4)

            await model.perform(.setDueDate("3"))
            #expect(try await store.cardCount(matching: "prop:due=3") == 4)
            #expect(await model.undoLastAction())
            #expect(try await store.cardCount(matching: "prop:due=3") == 0)

            #expect(await model.deletionSummary() == DeletionSummary(noteCount: 2, cardCount: 4))
            await model.perform(.delete)
            #expect(model.rowIDs.count == fields.count - 2)
            #expect(await model.undoLastAction())
            #expect(model.rowIDs.count == fields.count)
            #expect(model.searchedText == "deck:Languages")
        }
    }
}

extension BrowserParityTests {
    @Test("Bulk changes and undo retain the submitted query while an edit is still a draft")
    func undoWithDraftQuery() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let other = try await store.addDeck(named: "Japanese")
            let card = try await store.addBasicCard(front: "correr", back: "run", inDeck: deck)
            try await store.addBasicCard(front: "hashiru", back: "run", inDeck: other)
            let model = CardBrowserModel(store: store)
            model.searchText = "deck:Spanish"
            await model.search()
            model.selectAll()
            model.searchText = "deck:Japanese"
            await model.perform(.flag(.red))
            #expect(model.rowIDs == [card])
            #expect(model.searchedText == "deck:Spanish")
            #expect(model.searchText == "deck:Japanese")
            model.dismissCompletedAction()
            await model.undoCurrentAction()
            #expect(model.rowIDs == [card])
            #expect(try await store.cardCount(matching: "flag:1") == 0)
        }
    }
}

extension BrowserParityTests {
    @Test("Flag labels saved from Browse survive reopening without changing their searches")
    func customFlagLabels() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let card = try await store.addBasicCard(front: "correr", back: "run", inDeck: deck)
            let model = CardBrowserModel(store: store)
            await model.search()
            model.selectAll()
            await model.perform(.flag(.blue))
            await model.saveFlagNames([.blue: "Needs Audio"])
            let reopened = CardBrowserModel(store: store)
            await reopened.loadFlagNames()
            #expect(reopened.flagNames == [.blue: "Needs Audio"])
            await reopened.applyFilters([.flag(.blue)])
            #expect(reopened.rowIDs == [card])
            await reopened.saveFlagNames([.blue: " "])
            await model.loadFlagNames()
            #expect(model.flagNames.isEmpty)
        }
    }
}

extension BrowserParityTests {
    @Test("The filtered deck editor can build from the last submitted Browse search")
    func filteredDeckHandoff() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Languages")
            let selected = try await store.addBasicCard(front: "correr", back: "run", inDeck: deck, tags: ["verb"])
            try await store.addBasicCard(front: "rojo", back: "red", inDeck: deck)
            let browser = CardBrowserModel(store: store)
            await browser.applyFilters([.deck("Languages"), .tag("verb")])
            browser.searchText = "unsubmitted"
            let editor = FilteredDeckModel(store: store)
            await editor.load(initialSearch: browser.searchedText)
            #expect(editor.primary.search == browser.searchedText)
            editor.name = "Filtered"
            #expect(await editor.build() != nil)
            #expect(try await store.cardIDs(matching: "deck:Filtered") == [selected])
        }
    }
}

extension BrowserParityTests {
    @Test("Selection actions change note contents, card queues and scheduling through the core")
    func selectionActions() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Languages")
            let selected = try await store.addBasicCard(front: "correr", back: "run", inDeck: deck)
            let other = try await store.addBasicCard(front: "courir", back: "run", inDeck: deck)
            let browser = CardBrowserModel(store: store)
            await browser.search()
            browser.selection = [selected]

            await browser.perform(.addTags("verb"))
            #expect(try await store.cardIDs(matching: "tag:verb") == [selected])
            await browser.perform(.removeTags("verb"))
            #expect(try await store.cardCount(matching: "tag:verb") == 0)
            await browser.perform(.findAndReplace(search: "run", replacement: "sprint", field: "Back",
                tags: false, regex: false, matchCase: true, onlySelection: true))
            #expect(try await store.cardIDs(matching: "back:sprint") == [selected])
            #expect(try await store.cardIDs(matching: "back:run") == [other])

            await browser.perform(.toggleBury)
            #expect(try await store.cardIDs(matching: "is:buried") == [selected])
            await browser.perform(.toggleBury)
            #expect(try await store.cardCount(matching: "is:buried") == 0)
            await browser.perform(.toggleSuspend)
            #expect(try await store.cardIDs(matching: "is:suspended") == [selected])
            await browser.perform(.toggleSuspend)
            #expect(try await store.cardCount(matching: "is:suspended") == 0)

            let cardInfo = CardDetailModel(store: store, cardID: selected)
            await browser.perform(.reposition(start: 31, step: 1, randomize: false, shiftExisting: false))
            await cardInfo.refresh()
            #expect(cardInfo.detail?.due == .newCardPosition(31))
            #expect(await browser.undoLastAction())
            await browser.perform(.grade(.easy))
            await cardInfo.refresh()
            #expect(cardInfo.detail?.history.first?.rating == .easy)
            #expect(cardInfo.detail?.intervalDays ?? 0 > 0)
            await browser.perform(.resetProgress(restorePosition: true, resetCounts: true))
            #expect(try await store.cardIDs(matching: "is:review").isEmpty)
            #expect(await browser.undoLastAction())
            #expect(try await store.cardIDs(matching: "is:review") == [selected])
        }
    }
}

extension BrowserParityTests {
    @Test func mediaFilenamesCanBeShownWithoutChangingTheUnderlyingCard() async throws {
        try await withTemporaryCollection { store in
            let cardID = try await store.addBasicCard(front: "Word[sound:voice.mp3]", back: "Meaning", inDeck: 1)
            let browser = CardBrowserModel(store: store)
            await browser.search()
            await browser.setColumns(["question"])
            await browser.loadRow(cardID)
            let row = try #require(browser.row(for: cardID))
            #expect(row.displayText(for: "question", showsMediaFilenames: false).trimmingCharacters(in: .whitespacesAndNewlines) == "Word")
            #expect(row.displayText(for: "question", showsMediaFilenames: true).contains("voice.mp3"))
        }
    }
}
