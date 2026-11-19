import AnkiCore
import AnkiProto
import CollectionTesting
import NoteEditorFeature
import Testing

@MainActor
struct CardTemplateEditorTests {
    @Test func templateDraftRendersBothSidesAndSavesBrowserAppearance() async throws {
        try await withTemporaryCollection { store in
            let id = try await store.core.getNotetypeIdByName(.with { $0.val = "Basic" }).ntid
            let notes = try await store.addNotes(ofType: "Basic", fields: [["harbor", "port"]], toDeck: 1)
            let note = try #require(notes.first)
            let model = CardTemplateEditorModel(store: store, noteTypeID: id)
            try await model.load()
            model.setSource("<b>{{Front}}</b>", for: .front)
            model.setSource("Meaning: {{Back}}", for: .back)
            model.setSource(".card { color: purple; }", for: .styling)
            model.setSource("Term: {{Front}}", for: .browserFront)
            model.setSource("Gloss: {{Back}}", for: .browserBack)

            let study = try await model.preview()
            #expect(study.content.question.html.contains("<b>harbor</b>"))
            #expect(study.content.answer.html.contains("Meaning: port"))
            #expect(study.content.css.contains("color: purple"))
            let browser = try await model.preview(browser: true)
            #expect(browser.content.question.html.contains("Term: harbor"))
            #expect(browser.content.answer.html.contains("Gloss: port"))
            #expect(try await store.core.getNotetype(.with { $0.ntid = id }).templates[0].config.qFormat == "{{Front}}")

            #expect(try await model.save() == .saved)
            let cardID = try #require(try await store.core.cardsOfNote(.with { $0.nid = note }).cids.first)
            let render = try await store.core.renderExistingCard(.with {
                $0.cardID = cardID
                $0.browser = true
            })
            #expect(render.questionNodes.contains { $0.text.contains("Term: harbor") })
            #expect(render.answerNodes.contains { $0.text.contains("Gloss: port") })
        }
    }
}
