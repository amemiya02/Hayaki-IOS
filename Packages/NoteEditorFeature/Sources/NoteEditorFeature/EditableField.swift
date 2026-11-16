import Foundation

/// One field of a note as the learner edits it: plain text, plus images
/// attached to the field.
///
/// The field keeps the content it was stored with. Until the learner changes
/// the text or the images, `content` is that stored content, byte for byte,
/// so saving a note never alters a field nobody touched. Once changed, the
/// field is written as Anki writes typed text: special characters escaped,
/// line breaks as `<br>`, and each image as an `<img>` tag after the text.
public struct EditableField: Equatable, Sendable {
    public let name: String
    /// The field as the collection held it when the editor opened it (HTML).
    public let storedContent: String

    /// The field's text as the learner sees and edits it, without markup.
    public var text: String {
        didSet { if text != oldValue { isEdited = true } }
    }

    /// The media file names of the images attached to the field, in order.
    public private(set) var images: [String] {
        didSet { if images != oldValue { isEdited = true } }
    }

    /// Whether the learner changed the text or the images.
    public private(set) var isEdited = false

    public init(name: String, storedContent: String) {
        self.name = name
        self.storedContent = storedContent
        text = FieldMarkup.plainText(fromHTML: storedContent)
        images = FieldMarkup.imageNames(inHTML: storedContent)
    }

    /// What is saved in the note: the stored content if the learner left the
    /// field alone, otherwise the edited text and images.
    public var content: String {
        guard isEdited else { return storedContent }
        return FieldMarkup.html(fromPlainText: text)
            + images.map { "<img src=\"\(FieldMarkup.escaped($0, quotes: true))\">" }.joined()
    }

    mutating func attachImage(named name: String) {
        images.append(name)
    }

    mutating func removeImage(named name: String) {
        images.removeAll { $0 == name }
    }

    /// Takes over what the learner entered in a field of another note type.
    mutating func carryOver(_ other: EditableField) {
        text = other.text
        images = other.images
    }
}

/// Converting between field HTML and the plain text the editor shows.
enum FieldMarkup {
    /// Typed text as Anki stores it.
    static func html(fromPlainText text: String) -> String {
        escaped(text, quotes: false)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    static func escaped(_ text: String, quotes: Bool) -> String {
        var result = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        if quotes { result = result.replacingOccurrences(of: "\"", with: "&quot;") }
        return result
    }

    /// The text of field HTML, without tags: line breaks and block ends
    /// become new lines and common character references are decoded.
    static func plainText(fromHTML html: String) -> String {
        guard !html.isEmpty else { return "" }
        var text = html.replacing(/<br\s*\/?>|<\/(div|p|li)>/.ignoresCase(), with: "\n")
        text = text.replacing(/<[^>]*>/, with: "")
        for (reference, character) in [
            ("&nbsp;", "\u{A0}"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&"),
        ] {
            text = text.replacingOccurrences(of: reference, with: character)
        }
        return text
    }

    /// The file names of the images a field's HTML shows.
    static func imageNames(inHTML html: String) -> [String] {
        html.matches(of: /<img[^>]*?\ssrc\s*=\s*["']([^"']+)["']/.ignoresCase()).map {
            plainText(fromHTML: String($0.output.1))
        }
    }
}
