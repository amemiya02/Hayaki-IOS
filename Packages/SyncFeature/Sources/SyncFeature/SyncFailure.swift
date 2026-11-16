import AnkiCore
import Foundation

/// Why signing in or a sync did not complete, said plainly, with the core's
/// own description of the cause where it adds something.
public struct SyncFailure: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// The address is not a web address starting with http:// or https://.
        case invalidAddress
        /// The server refused the user name and password, or the stored key.
        case wrongCredentials
        /// The server could not be reached.
        case unreachable
        /// The learner cancelled.
        case cancelled
        /// The server explained why it would not sync.
        case serverMessage
        /// The Keychain could not be read or written.
        case secureStorage
        case other
    }

    public let reason: Reason
    /// What happened, in the app's words.
    public let message: String
    /// The underlying cause as the core or the system reported it, if any.
    public let detail: String?

    init(reason: Reason, message: String? = nil, detail: String? = nil) {
        self.reason = reason
        self.message = message ?? Self.message(for: reason)
        self.detail = detail
    }

    init(storageError error: any Error) {
        self.init(reason: .secureStorage, detail: error.localizedDescription)
    }

    init(_ error: CoreError, server: URL, signingIn: Bool) {
        let host = server.host() ?? server.absoluteString
        switch error.kind {
        case .syncAuthError:
            self.init(reason: .wrongCredentials, message: signingIn
                ? String(localized: "The server did not accept this user name and password.", bundle: .module)
                : String(localized: "The server no longer accepts this device's sign-in. Sign out, then sign in again.", bundle: .module))
        case .networkError:
            self.init(
                reason: .unreachable,
                message: String(localized: "Could not reach the sync server at \(host). Check the address, and that the server is running and reachable from this device.", bundle: .module),
                detail: error.message
            )
        case .interrupted:
            self.init(reason: .cancelled, message: signingIn
                ? String(localized: "Signing in was cancelled.", bundle: .module)
                : String(localized: "The sync was cancelled before it finished.", bundle: .module))
        case .syncServerMessage:
            self.init(reason: .serverMessage, message: error.message)
        case .invalidInput where signingIn:
            self.init(reason: .invalidAddress, detail: error.message)
        default:
            // Some of the core's sync messages are written for AnkiWeb, which
            // Hayaki never talks to; those would mislead, so they are left out.
            self.init(
                reason: .other,
                message: signingIn
                    ? String(localized: "Signing in failed.", bundle: .module)
                    : String(localized: "The sync failed.", bundle: .module),
                detail: error.message.localizedCaseInsensitiveContains("AnkiWeb") ? nil : error.message
            )
        }
    }

    private static func message(for reason: Reason) -> String {
        switch reason {
        case .invalidAddress:
            String(localized: "Enter the server's full address, starting with http:// or https://.", bundle: .module)
        case .secureStorage:
            String(localized: "Could not use the device's secure storage for the sign-in.", bundle: .module)
        case .cancelled:
            String(localized: "The sync was cancelled before it finished.", bundle: .module)
        case .wrongCredentials, .unreachable, .serverMessage, .other:
            String(localized: "The sync failed.", bundle: .module)
        }
    }
}
