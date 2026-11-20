import Foundation

/// What the glass strip above the tab bar (or at the foot of the iPad
/// sidebar) shows: a sync under way, its brief success, or a failure that
/// waits for Retry. Nil hides the strip.
public enum SyncAccessory: Equatable, Sendable {
    public struct Progress: Equatable, Sendable {
        /// Completed fraction, when the size of the transfer is known.
        public let fraction: Double?
        /// What is happening, with the core's counts when it reports them.
        public let line: String
    }

    /// What Retry repeats.
    public enum RetryAction: Equatable, Sendable {
        case collection
        case media
    }

    case running(Progress)
    case succeeded
    case failed(SyncFailure, retry: RetryAction)

    /// The strip after the sync state changed. Only a sync seen running
    /// leads to success or failure, so a result restored at launch, a
    /// sign-in, or a cancelled sync shows nothing.
    public static func next(
        after previous: SyncAccessory?,
        status: SyncModel.Status,
        mediaStatus: MediaSyncStatus
    ) -> SyncAccessory? {
        if case .syncing(let progress) = status {
            return .running(Progress(collection: progress))
        }
        if case .syncing(let progress) = mediaStatus {
            return .running(Progress(media: progress))
        }
        guard let previous else { return nil }

        switch status {
        case .failed(let failure):
            return failure.reason == .cancelled ? nil : .failed(failure, retry: .collection)
        case .synced:
            switch mediaStatus {
            case .failed(let failure):
                return .failed(failure ?? SyncFailure(reason: .other), retry: .media)
            case .synced, .idle:
                // A success that is already showing stays until its timer ends.
                if case .failed = previous { return previous }
                return .succeeded
            case .cancelled, .interrupted, .syncing:
                return nil
            }
        case .idle, .signingIn, .choosingDirection, .fullSyncRequested, .syncing:
            return nil
        }
    }
}

extension SyncAccessory.Progress {
    init(collection progress: SyncProgress) {
        switch progress {
        case .connecting:
            fraction = nil
            line = String(localized: "Connecting…", bundle: .module)
        case .syncing(let detail):
            fraction = nil
            line = Self.join(String(localized: "Syncing Collection", bundle: .module), detail)
        case .uploading(let transferred, let total):
            fraction = Self.fraction(transferred, of: total)
            line = String(localized: "Uploading Collection", bundle: .module)
        case .downloading(let transferred, let total):
            fraction = Self.fraction(transferred, of: total)
            line = String(localized: "Downloading Collection", bundle: .module)
        }
    }

    init(media progress: MediaSyncProgress?) {
        fraction = nil
        line = Self.join(
            String(localized: "Syncing Media", bundle: .module),
            progress.map { [$0.checked, $0.added, $0.removed].joined(separator: " · ") }
        )
    }

    private static func join(_ title: String, _ detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return title }
        return "\(title) · \(detail)"
    }

    private static func fraction(_ transferred: Int, of total: Int) -> Double? {
        total > 0 ? Double(min(transferred, total)) / Double(total) : nil
    }
}
