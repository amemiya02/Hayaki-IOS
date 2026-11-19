import BrowseFeature
import CollectionStore
import CollectionTesting
import Foundation
import Testing

/// The browser over a collection of one hundred thousand cards.
@MainActor
@Suite("Large collection", .timeLimit(.minutes(5)))
struct LargeCollectionTests {
    static let cardCount = 100_000

    @Test("Rows are fetched a page at a time, so a search over 100,000 cards and scrolling stay quick")
    func pagedLoading() async throws {
        try await withTemporaryCollection { store in
            let english = try await store.addDeck(named: "English")
            let french = try await store.addDeck(named: "French")
            // Notes added in large batches, alternating decks by batch.
            let batch = 20_000
            for start in stride(from: 0, to: Self.cardCount, by: batch) {
                let fields = (start ..< start + batch).map { [String(format: "word %06d", $0), "meaning \($0)"] }
                try await store.addNotes(ofType: "Basic", fields: fields, toDeck: start / batch % 2 == 0 ? english : french)
            }
            let clock = ContinuousClock()
            let model = CardBrowserModel(store: store)

            // Searching the whole collection lists every card at once...
            let searching = await clock.measure { await model.search() }
            #expect(model.state == .loaded)
            #expect(model.cardIDs.count == Self.cardCount)
            // ...but fetches no row yet.
            #expect(model.row(for: model.cardIDs[0]) == nil)

            // A row appearing far down the list fetches its page of rows.
            let pageSize = CardBrowserModel.pageSize
            let index = 50_010
            let pageStart = index / pageSize * pageSize
            let paging = await clock.measure { await model.loadRow(model.cardIDs[index]) }
            #expect(model.row(for: model.cardIDs[index])?.question == String(format: "word %06d", index))
            for i in pageStart ..< pageStart + pageSize {
                #expect(model.row(for: model.cardIDs[i]) != nil, "row \(i) of the page not fetched")
            }
            // Nothing outside that page.
            #expect(model.row(for: model.cardIDs[pageStart - 1]) == nil)
            #expect(model.row(for: model.cardIDs[pageStart + pageSize]) == nil)
            #expect(model.row(for: model.cardIDs[0]) == nil)

            // Scrolling on: each row of the next page appears, one page is fetched.
            let scrolling = await clock.measure {
                for i in pageStart + pageSize ..< pageStart + 2 * pageSize {
                    await model.loadRow(model.cardIDs[i])
                }
            }
            #expect(model.row(for: model.cardIDs[pageStart + 2 * pageSize - 1]) != nil)
            #expect(model.row(for: model.cardIDs[pageStart + 2 * pageSize]) == nil)

            // A filter, and a sort by another column, are quick too.
            let filtering = await clock.measure { await model.applyFilter(.deck("French")) }
            #expect(model.cardIDs.count == 40_000)
            let created = try #require(model.sortColumns.first { $0.id == "noteCrt" })
            let sorting = await clock.measure { await model.sortBy(created) }
            #expect(model.cardIDs.count == 40_000)

            // Selecting every card and acting on them all works at this size.
            model.selectAll()
            var summary: DeletionSummary?
            let summarizing = await clock.measure { summary = await model.deletionSummary() }
            #expect(summary == DeletionSummary(noteCount: 40_000, cardCount: 40_000))
            let suspending = await clock.measure { await model.perform(.suspend) }
            #expect(model.failure == nil)
            #expect(try await store.cardCount(matching: "is:suspended") == 40_000)

            #expect(await model.undoLastAction())
            #expect(try await store.cardCount(matching: "is:suspended") == 0)
            await model.setMode(.notes)
            #expect(model.rowIDs.count == 40_000)
            let firstNote = try #require(model.rowIDs.first)
            let lastNote = try #require(model.rowIDs.last)
            await model.loadRow(firstNote)
            model.selection.insert(firstNote)
            await model.loadRow(lastNote)
            model.selection.insert(lastNote)
            await model.perform(.flag(.red))
            #expect(try await store.cardCount(matching: "flag:1") == 2)
            #expect(await model.undoLastAction())
            #expect(try await store.cardCount(matching: "flag:1") == 0)
            #expect(model.selection == [firstNote, lastNote])

            print("""
                100,000 cards: search \(searching), first page \(paging), next page \(scrolling), \
                filter \(filtering), sort \(sorting), deletion summary \(summarizing), suspend 40,000 \(suspending)
                """)
            // Generous bounds: this runs on shared, often heavily loaded machines.
            #expect(searching < .seconds(5))
            #expect(paging < .seconds(2))
            #expect(scrolling < .seconds(2))
            #expect(filtering < .seconds(5))
            #expect(sorting < .seconds(5))
            #expect(summarizing < .seconds(5))
            #expect(suspending < .seconds(10))
        }
    }
}
