import Foundation

/// Only profile and deck identifiers travel in URLs, never note contents.
public enum DeckLink: Equatable, Sendable {
    public enum Action: String, Sendable {
        case study
        case options
    }

    case decks(profileID: UUID?)
    case deck(profileID: UUID, deckID: Int64, action: Action)

    public var profileID: UUID? {
        switch self {
        case .decks(let id): id
        case .deck(let id, _, _): id
        }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = "hayaki"
        components.host = "decks"
        switch self {
        case .decks(let profileID):
            components.path = profileID.map { "/\($0.uuidString)" } ?? ""
        case .deck(let profileID, let deckID, let action):
            components.path = "/\(profileID.uuidString)/\(deckID)/\(action.rawValue)"
        }
        return components.url!
    }

    public init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "hayaki", parts.host == "decks", parts.query == nil,
              parts.fragment == nil, parts.user == nil, parts.password == nil, parts.port == nil
        else { return nil }
        let path = parts.path.split(separator: "/", omittingEmptySubsequences: false)
        if parts.path.isEmpty {
            self = .decks(profileID: nil)
        } else if path.count == 2, let profileID = UUID(uuidString: String(path[1])) {
            self = .decks(profileID: profileID)
        } else if path.count == 4, let profileID = UUID(uuidString: String(path[1])),
                  let deckID = Int64(path[2]), deckID > 0, let action = Action(rawValue: String(path[3])) {
            self = .deck(profileID: profileID, deckID: deckID, action: action)
        } else {
            return nil
        }
    }
}
