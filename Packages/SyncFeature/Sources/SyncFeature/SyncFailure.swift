import AnkiCore
import Foundation

/// Why signing in or a sync did not complete, said plainly, with the core's
/// own description of the cause where it adds something.
public struct SyncFailure: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// The address is not a web address starting with http:// or https://.
        case invalidAddress
        case invalidCertificate
        /// The server refused the user name and password, or the stored key.
        case wrongCredentials
        /// The server could not be reached.
        case unreachable
        /// The learner cancelled.
        case cancelled
        /// The server explained why it would not sync.
        case serverMessage
        /// A redirect would leave the selected sync destination.
        case unexpectedRedirect
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

    init(_ error: CoreError, server: URL?, signingIn: Bool) {
        switch error.kind {
        case .syncAuthError:
            self.init(reason: .wrongCredentials, message: signingIn
                ? String(localized: "The server did not accept this user name and password.", bundle: .module)
                : String(localized: "The server no longer accepts this device's sign-in. Sign out, then sign in again.", bundle: .module))
        case .networkError:
            let message: String
            if let server {
                let host = server.host() ?? server.absoluteString
                message = String(localized: "Could not reach the sync server at \(host). Check the address, and that the server is running and reachable from this device.", bundle: .module)
            } else {
                message = String(localized: "Could not reach AnkiWeb. Check your internet connection and try again.", bundle: .module)
            }
            self.init(reason: .unreachable, message: message, detail: error.message)
        case .interrupted:
            self.init(reason: .cancelled, message: signingIn
                ? String(localized: "Signing in was cancelled.", bundle: .module)
                : String(localized: "The sync was cancelled before it finished.", bundle: .module))
        case .syncServerMessage:
            self.init(reason: .serverMessage, message: error.message)
        case .invalidInput where signingIn && server != nil:
            self.init(reason: .invalidAddress, detail: error.message)
        default:
            // The core can mention AnkiWeb in advice for a self-hosted server.
            self.init(
                reason: .other,
                message: signingIn
                    ? String(localized: "Signing in failed.", bundle: .module)
                    : String(localized: "The sync failed.", bundle: .module),
                detail: server != nil && error.message.localizedCaseInsensitiveContains("AnkiWeb") ? nil : error.message
            )
        }
    }

    private static func message(for reason: Reason) -> String {
        switch reason {
        case .invalidAddress:
            String(localized: "Enter the server's full address, starting with http:// or https://.", bundle: .module)
        case .invalidCertificate:
            String(localized: "Enter one valid PEM certificate for an HTTPS sync server.", bundle: .module)
        case .unexpectedRedirect:
            String(localized: "The sync server redirected to an address outside the selected destination.", bundle: .module)
        case .secureStorage:
            String(localized: "Could not use the device's secure storage for the sign-in.", bundle: .module)
        case .cancelled:
            String(localized: "The sync was cancelled before it finished.", bundle: .module)
        case .wrongCredentials, .unreachable, .serverMessage, .other:
            String(localized: "The sync failed.", bundle: .module)
        }
    }
}
