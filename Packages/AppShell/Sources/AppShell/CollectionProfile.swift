import Foundation

/// A local study environment with a collection and a sync destination of its own.
public struct CollectionProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String

    static let legacyID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    static let legacy = CollectionProfile(id: legacyID, name: "Default")

    var usesLegacyStorage: Bool { id == Self.legacyID }
}

public enum ProfileError: LocalizedError, Equatable {
    case emptyName
    case nameTooLong
    case duplicateName
    case unavailable
    case lastProfile
    case activeProfile
    case busy

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            String(localized: "Enter a profile name.", bundle: .module)
        case .nameTooLong:
            String(localized: "Enter a profile name of 50 characters or fewer.", bundle: .module)
        case .duplicateName:
            String(localized: "A profile already uses this name.", bundle: .module)
        case .unavailable:
            String(localized: "This profile is unavailable.", bundle: .module)
        case .lastProfile:
            String(localized: "Keep at least one profile.", bundle: .module)
        case .activeProfile:
            String(localized: "Switch to another profile before deleting the current one.", bundle: .module)
        case .busy:
            String(localized: "Wait for the current collection operation to finish, then try again.", bundle: .module)
        }
    }
}
