import Foundation
import Synchronization

/// How Hayaki names itself to a sync server.
///
/// The core reports the client at the start of every sync as
/// `anki,<core version> (<build hash>),<platform>`, taking `<platform>` from
/// the `PLATFORM` environment variable the first time it syncs (see
/// `sync_client_version` in the core's `version.rs`); without it the core
/// would report only the operating system, as the official iOS app does. The
/// platform is set here to `hayaki:<app version>:<os>:<os version>`, for
/// example `hayaki:0.1.0:ios:27.0`. The build hash, sent with every request,
/// names Hayaki's build of the core too (`hayaki-<Anki commit>`, set by
/// `scripts/build-core.sh`).
public enum SyncClientIdentity {
    /// The platform Hayaki reports, such as `hayaki:0.1.0:ios:27.0`.
    public static var platform: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "hayaki:\(version):\(operatingSystem):\(os.majorVersion).\(os.minorVersion)"
    }

    /// The operating system Hayaki runs on, named as the core names it.
    /// (Tests run the same code on the Mac, which reports itself as macOS.)
    static var operatingSystem: String {
        #if os(iOS)
        "ios"
        #elseif os(macOS)
        "macos"
        #else
        "unknown"
        #endif
    }

    private static let installed = Mutex(false)

    /// Sets `PLATFORM` once, before the first call into the core's sync. The
    /// core reads it only once per process, at the first sync.
    static func install() {
        installed.withLock { installed in
            guard !installed else { return }
            setenv("PLATFORM", platform, 1)
            installed = true
        }
    }
}
