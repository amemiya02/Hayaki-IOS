import AnkiCore
import AnkiProto
import CollectionStore
import CollectionTesting
import Foundation
import NoteEditorFeature
import Testing

@MainActor
struct NoteTypeConversionTests {
    @Test func conversionPreservesMappedContentAndSchedulingAndWaitsForConfirmation() async throws {
        try await withTemporaryCollection { store in
            let notes = try await store.addNotes(ofType: "Basic", fields: [["<b>harbor</b>", "port"]], toDeck: 1)
            let noteID = try #require(notes.first)
            let cardID = try #require(try await store.core.cardsOfNote(.with { $0.nid = noteID }).cids.first)
            try await store.modify(.setDueDate(.with {
                $0.cardIds = [cardID]
                $0.days = "12!"
            }))
            let original = try await store.core.getCard(.with { $0.cid = cardID })
            #expect(original.interval == 12)
            // A collection whose last sync already included its current schema.
            let stamp = #"{"kind":"query","sql":"update col set ls = scm","args":[],"first_row_only":false}"#
            _ = try await store.core.runDbCommand(.with { $0.json = Data(stamp.utf8) })
            let target = try await store.core.getNotetypeIdByName(.with { $0.val = "Basic (and reversed card)" }).ntid
            let model = NoteTypeConversionModel(store: store, noteIDs: [noteID, noteID])
            try await model.load()
            try await model.chooseDestination(target)
            model.mapField(1, from: 0)
            model.mapField(0, from: 1)
            model.mapTemplate(1, from: 0)

            let preview = try await model.preview()
            #expect(preview.map(\.name) == ["Card 1", "Card 2"])
            #expect(preview[0].content.question.html.contains("port"))
            #expect(preview[1].content.question.html.contains("<b>harbor</b>"))
            #expect(try await model.save() == .needsFullSyncConfirmation)
            #expect(try await store.core.getNote(.with { $0.nid = noteID }).fields == ["<b>harbor</b>", "port"])
            #expect(try await store.core.getCard(.with { $0.cid = cardID }) == original)

            #expect(try await model.save(confirmingFullSync: true) == .saved)
            let converted = try await store.core.getNote(.with { $0.nid = noteID })
            let retained = try await store.core.getCard(.with { $0.cid = cardID })
            #expect(converted.notetypeID == target)
            #expect(converted.fields == ["port", "<b>harbor</b>"])
            #expect(retained.templateIdx == 1)
            #expect(retained.interval == original.interval)
            #expect(retained.due == original.due)
            #expect(retained.queue == original.queue)
            #expect(try await store.core.cardsOfNote(.with { $0.nid = noteID }).cids.count == 2)
        }
    }
}
