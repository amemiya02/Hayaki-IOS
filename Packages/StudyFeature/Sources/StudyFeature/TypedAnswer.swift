import AnkiCore
import AnkiProto
import Foundation

/// What a card that asks the learner to type the answer (`{{type:Field}}` in
/// its template) expects, found on its question side as desktop Anki's
/// reviewer finds it.
struct TypedAnswerPrompt: Equatable, Sendable {
    /// The expected answer: the field's content, or for `{{type:cloze:Field}}`
    /// the card's own cloze deletions in it.
    let expected: String
    /// Whether the comparison treats a letter and its combining accents as
    /// one (`{{type:nc:Field}}` turns this off).
    let combining: Bool
    /// The field's editing font and size from the note type, which the text
    /// field and the comparison are shown in.
    let fontName: String
    let fontSize: UInt32

    /// Everything `[[type:…]]` the core leaves where a template has
    /// `{{type:…}}`.
    nonisolated(unsafe) private static let marker = /\[\[type:(.+?)\]\]/

    static func containsMarker(_ html: String) -> Bool {
        html.contains(marker)
    }

    /// Finds what the question side's first `{{type:…}}` expects, and puts a
    /// text field in place of every one. Without a marker the HTML comes back
    /// unchanged and there is no prompt.
    static func questionSide(
        _ html: String,
        card: Anki_Cards_Card,
        core: CoreClient
    ) async throws(CoreError) -> (html: String, prompt: TypedAnswerPrompt?) {
        guard let match = html.firstMatch(of: marker) else { return (html, nil) }
        var name = String(match.output.1)
        var clozeOrdinal: UInt32?
        var combining = true
        if name.hasPrefix("cloze:") {
            clozeOrdinal = card.templateIdx + 1
            name.removeFirst("cloze:".count)
        }
        if name.hasPrefix("nc:") {
            combining = false
            name.removeFirst("nc:".count)
        }

        let note = try await core.getNote(.with { $0.nid = card.noteID })
        let notetype = try await core.getNotetype(.with { $0.ntid = note.notetypeID })
        guard let index = notetype.fields.firstIndex(where: { $0.name == name }), index < note.fields.count else {
            let warning = String(
                localized: "The card asks to type the field “\(name)”, which its note type does not have.",
                bundle: .module,
                comment: "Shown on a card whose template asks to type the answer into a field that does not exist."
            )
            return (html.replacing(marker, with: HTML.escape(warning)), nil)
        }
        var expected = note.fields[index]
        if let clozeOrdinal {
            expected = try await core.extractClozeForTyping(.with {
                $0.text = expected
                $0.ordinal = clozeOrdinal
            }).val
        }
        // Nothing to type: the field (or the card's deletion) is empty.
        guard !expected.isEmpty else { return (html.replacing(marker, with: ""), nil) }

        let field = notetype.fields[index].config
        let prompt = TypedAnswerPrompt(
            expected: expected,
            combining: combining,
            fontName: field.fontName,
            fontSize: field.fontSize
        )
        return (html.replacing(marker, with: prompt.textField), prompt)
    }

    /// The answer side with the core's comparison of what was typed with
    /// the expected answer in place of each `{{type:…}}`; or, for a card
    /// without a prompt, with the markers removed. As in Anki, a
    /// `<hr id=answer>` separator moves to just above the comparison, so it
    /// stays between question and answer when the template shows the
    /// question with `{{FrontSide}}`.
    static func answerSide(
        _ html: String,
        prompt: TypedAnswerPrompt?,
        typed: String,
        core: CoreClient
    ) async throws(CoreError) -> String {
        guard let prompt else { return html.replacing(marker, with: "") }
        guard html.contains(marker) else { return html }
        let comparison = try await core.compareAnswer(.with {
            $0.expected = prompt.expected
            $0.provided = typed
            $0.combining = prompt.combining
        }).val
        let separator = "<hr id=answer>"
        let hadSeparator = html.contains(separator)
        let withoutSeparator = html.replacing(separator, with: "")
        let shown = "<div style=\"\(prompt.fontStyle)\">\(comparison)</div>"
        return withoutSeparator.replacing(marker, with: hadSeparator ? separator + shown : shown)
    }

    private var fontStyle: String {
        var style = "font-size: \(fontSize > 0 ? fontSize : 20)px"
        if !fontName.isEmpty {
            style = "font-family: '\(HTML.escape(fontName))'; " + style
        }
        return style
    }

    /// The text field the learner types into. The card host page sends
    /// what is typed to native code, and Return shows the answer.
    private var textField: String {
        let label = String(
            localized: "Type the Answer",
            bundle: .module,
            comment: "VoiceOver label and placeholder of the text field on a card that asks the learner to type the answer."
        )
        return """
        <center><input type="text" id=typeans autocomplete="off" autocorrect="off" \
        autocapitalize="off" spellcheck="false" enterkeyhint="done" \
        placeholder="\(HTML.escape(label))" aria-label="\(HTML.escape(label))" \
        style="\(fontStyle)"></center>
        """
    }
}
