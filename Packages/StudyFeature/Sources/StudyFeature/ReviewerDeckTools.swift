import Foundation

/// Whiteboard and pronunciation choices for the deck the learner selected.
public struct ReviewerDeckTools: Codable, Equatable, Sendable {
    public var whiteboardEnabled = false
    public var drawingShown = true
    public var stylusOnly = false
    public var recorderShown = false
    public var penColor = "automatic"
    public var penWidth = 4.0
    public var eraserWidth = 24.0
    public var strokeEraser = false
    public var toolbarTop = false

    public init() {}

    public static func load(profile: URL, deckID: Int64, defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: key(profile: profile, deckID: deckID)),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    public func save(profile: URL, deckID: Int64, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key(profile: profile, deckID: deckID))
    }

    private static func key(profile: URL, deckID: Int64) -> String {
        "reviewer.tools.\(Data(profile.standardizedFileURL.path.utf8).base64EncodedString()).\(deckID)"
    }
}
