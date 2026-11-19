@testable import NoteEditorFeature
import Testing

@Suite("Note formatting toolbar")
struct EditorFormattingTests {
    @Test("The font-size options use the Android toolbar's seven CSS sizes")
    func fontSizeOptions() {
        let field = EditableField(name: "Front", storedContent: "Size A &amp; B")
        let text = field.text
        let selected = text.index(text.startIndex, offsetBy: 5)..<text.endIndex
        let results = EditorFontSize.allCases.map { size in
            EditorTextFormat.fontSize(size).apply(to: field, selection: selected, editingMarkup: false, fields: [field])
        }

        #expect(results.map(\.html) == [
            #"Size <span style="font-size:xx-small">A &amp; B</span>"#,
            #"Size <span style="font-size:x-small">A &amp; B</span>"#,
            #"Size <span style="font-size:small">A &amp; B</span>"#,
            #"Size <span style="font-size:medium">A &amp; B</span>"#,
            #"Size <span style="font-size:large">A &amp; B</span>"#,
            #"Size <span style="font-size:x-large">A &amp; B</span>"#,
            #"Size <span style="font-size:xx-large">A &amp; B</span>"#,
        ])
        #expect(results.allSatisfy { $0.html[$0.selection] == "A &amp; B" })
    }

    @Test("Chemistry wraps the selected formula in Anki MathJax markup")
    func formatsSelectedChemistry() {
        let field = EditableField(name: "Front", storedContent: "<b>Water</b> H2O and salt")
        let text = field.content
        let start = text.index(text.startIndex, offsetBy: 13)
        let selected = start..<text.index(start, offsetBy: 3)

        let result = EditorTextFormat.chemistryMath.apply(
            to: field, selection: selected, editingMarkup: true, fields: [field]
        )

        #expect(result.html == #"<b>Water</b> \( \ce{H2O} \) and salt"#)
        #expect(result.html[result.selection] == "H2O")
    }
}
