import Foundation

/// A field keeps its original HTML and changes only when the learner edits it.
public struct EditableField: Equatable, Sendable {
    public let name: String
    public let storedContent: String
    public private(set) var content: String
    public var text: String { FieldMarkup.plainText(fromHTML: content) }
    public var images: [String] { FieldMarkup.imageNames(inHTML: content) }
    public var isEdited: Bool { !storedContent.utf8.elementsEqual(content.utf8) }

    /// Text that can be represented losslessly by the plain-text editor,
    /// with canonical image tags at its end.
    public var requiresMarkup: Bool {
        !content.utf8.elementsEqual(Self.plainHTML(text, images: images).utf8)
    }

    public init(name: String, storedContent: String) {
        self.name = name
        self.storedContent = storedContent
        content = storedContent
    }

    mutating func setText(_ text: String) {
        guard !requiresMarkup else { return }
        content = Self.plainHTML(text, images: images)
    }

    mutating func setMarkup(_ markup: String) {
        content = markup
    }

    mutating func attachImage(named name: String) {
        content += Self.imageHTML(named: name)
    }

    mutating func removeImage(named name: String) {
        content = content.replacing(FieldMarkup.imageTag) { match in
            FieldMarkup.plainText(fromHTML: String(match.output.1)) == name
                ? ""
                : String(match.output.0)
        }
    }

    private static func plainHTML(_ text: String, images: [String]) -> String {
        FieldMarkup.html(fromPlainText: text) + images.map(Self.imageHTML).joined()
    }

    private static func imageHTML(named name: String) -> String {
        "<img src=\"\(FieldMarkup.escaped(name, quotes: true))\">"
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

    nonisolated(unsafe) static let imageTag = /<img\b[^>]*?\ssrc\s*=\s*["']([^"']+)["'][^>]*>/.ignoresCase()

    /// The file names of the images a field's HTML shows.
    static func imageNames(inHTML html: String) -> [String] {
        html.matches(of: imageTag).map {
            plainText(fromHTML: String($0.output.1))
        }
    }
}
