import AnkiProto
import Foundation

/// One thing a card plays: a sound or video file from the collection's media
/// folder, or text read aloud by the device's speech synthesizer.
public enum CardSound: Equatable, Sendable {
    /// A file in the media folder, from a `[sound:…]` reference.
    case file(URL)
    /// Text to speech, from a `{{tts …}}` field or an `[anki:tts …]` tag.
    case speech(Speech)

    /// Text to speech as the card's template asks for it.
    public struct Speech: Equatable, Sendable {
        /// The text to read, without HTML.
        public let text: String
        /// The language as Anki writes it, such as `en_US` or `ja_JP`.
        public let language: String
        /// Preferred voice names, best first; may be empty.
        public let voices: [String]
        /// Anki's speed factor: 1 is normal speed.
        public let speed: Float

        public init(text: String, language: String, voices: [String], speed: Float) {
            self.text = text
            self.language = language
            self.voices = voices
            self.speed = speed
        }
    }

    init(_ tag: Anki_CardRendering_AVTag, mediaFolder: URL) {
        switch tag.value {
        case .soundOrVideo(let name):
            self = .file(mediaFolder.appendingPathComponent(name, isDirectory: false))
        case .tts(let tts):
            self = .speech(Speech(text: tts.fieldText, language: tts.lang, voices: tts.voices, speed: tts.speed))
        case nil:
            self = .speech(Speech(text: "", language: "", voices: [], speed: 1))
        }
    }
}

/// The deck options that decide when a card's audio plays.
struct AudioOptions: Equatable, Sendable {
    /// "Don't play audio automatically" is off.
    var autoplay = true
    /// "Skip question when replaying answer" is off.
    var replaysQuestionOnAnswer = true
}

/// Turns the core's `[anki:play:q:0]` markers into replay buttons that the
/// card host page sends back as `play` messages, as desktop Anki's reviewer
/// draws them.
enum PlayButtons {
    static func insert(into html: String, label: String) -> String {
        let escapedLabel = HTML.escape(label)
        // The marker the core leaves for each audio reference, numbered per side.
        return html.replacing(/\[anki:play:([qa]):(\d+)\]/) { match in
            let id = "\(match.output.1):\(match.output.2)"
            return """
            <a class="replay-button soundLink" href="#" data-play="\(id)" role="button" \
            aria-label="\(escapedLabel)" draggable="false">\
            <svg class="playImage" viewBox="0 0 64 64" version="1.1" aria-hidden="true">\
            <circle cx="32" cy="32" r="29" />\
            <path d="M56.502,32.301l-37.502,20.101l0.329,-40.804l37.173,20.703Z" /></svg></a>
            """
        }
    }

    /// Splits a button's id such as `q:0` into its side and index.
    static func parse(_ id: String) -> (isQuestion: Bool, index: Int)? {
        let parts = id.split(separator: ":")
        guard parts.count == 2, let index = Int(parts[1]), index >= 0 else { return nil }
        switch parts[0] {
        case "q": return (true, index)
        case "a": return (false, index)
        default: return nil
        }
    }
}

enum HTML {
    /// Escapes text for use inside HTML text or a quoted attribute.
    static func escape(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&#39;"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}
