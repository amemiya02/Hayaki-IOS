import Foundation
import Network

public struct SyncPolicy: Codable, Equatable, Sendable {
    public enum Media: String, Codable, CaseIterable, Sendable {
        case always
        case onlyUnmetered
        case never

        func allows(_ network: SyncNetwork?) -> Bool {
            switch self {
            case .always: true
            case .onlyUnmetered: network == .unmetered
            case .never: false
            }
        }
    }

    public static let timeoutRange = 30...99_999

    public var automatic = false
    public var showsStatusBadge = true
    public var allowsMetered = false
    public var media: Media = .always
    public private(set) var timeoutSeconds = 60

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case automatic, showsStatusBadge, allowsMetered, media, timeoutSeconds
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        automatic = try values.decodeIfPresent(Bool.self, forKey: .automatic) ?? false
        showsStatusBadge = try values.decodeIfPresent(Bool.self, forKey: .showsStatusBadge) ?? true
        allowsMetered = try values.decodeIfPresent(Bool.self, forKey: .allowsMetered) ?? false
        media = try values.decodeIfPresent(Media.self, forKey: .media) ?? .always
        if let savedTimeout = try values.decodeIfPresent(Int.self, forKey: .timeoutSeconds) {
            _ = setTimeoutSeconds(savedTimeout)
        }
    }

    @discardableResult
    public mutating func setTimeoutSeconds(_ seconds: Int) -> Bool {
        guard Self.timeoutRange.contains(seconds) else { return false }
        timeoutSeconds = seconds
        return true
    }
}

public enum SyncNetwork: Equatable, Sendable {
    case offline
    case metered
    case unmetered

    init(_ path: NWPath) {
        if path.status != .satisfied {
            self = .offline
        } else if path.isExpensive || path.isConstrained {
            self = .metered
        } else {
            self = .unmetered
        }
    }
}
