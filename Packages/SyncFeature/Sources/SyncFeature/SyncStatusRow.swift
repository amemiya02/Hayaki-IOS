import Foundation

/// What one row of the Sync screen shows for the collection or for media:
/// a status icon and text, the last sync time, progress while running, and
/// the failure to explain in the row below.
struct SyncStatusRow: Equatable {
    enum Kind: Equatable {
        case notSynced
        case syncing
        case synced
        case cancelled
        case interrupted
        case failed
        /// The collection waits for an upload or download choice, or a
        /// requested one-way sync.
        case oneWay
    }

    let kind: Kind
    let lastSynced: Date?
    /// Completed fraction, when the size of the transfer is known.
    var fraction: Double?
    /// Counts the core reports while running, on one line.
    var progressDetail: String?
    var failure: SyncFailure?

    var isRunning: Bool { kind == .syncing }
    var isFailed: Bool { kind == .failed }

    var status: String {
        switch kind {
        case .notSynced: String(localized: "Not Synced Yet", bundle: .module)
        case .syncing: String(localized: "Syncing…", bundle: .module)
        case .synced: String(localized: "Synced", bundle: .module)
        case .cancelled: String(localized: "Cancelled", bundle: .module)
        case .interrupted: String(localized: "Interrupted", bundle: .module)
        case .failed: String(localized: "Failed", bundle: .module)
        case .oneWay: String(localized: "One-Way Sync Needed", bundle: .module)
        }
    }

    var systemImage: String {
        switch kind {
        case .notSynced: "circle.dashed"
        case .syncing: "arrow.triangle.2.circlepath"
        case .synced: "checkmark.circle.fill"
        case .cancelled: "xmark.circle.fill"
        case .interrupted: "pause.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .oneWay: "arrow.up.arrow.down.circle.fill"
        }
    }

    init(media status: MediaSyncStatus, lastSynced: Date?) {
        self.lastSynced = lastSynced
        switch status {
        case .idle:
            kind = lastSynced == nil ? .notSynced : .synced
        case .syncing(let progress):
            kind = .syncing
            progressDetail = progress.map { [$0.checked, $0.added, $0.removed].joined(separator: " · ") }
        case .synced:
            kind = .synced
        case .cancelled:
            kind = .cancelled
        case .interrupted:
            kind = .interrupted
        case .failed(let failure):
            kind = .failed
            self.failure = failure
        }
    }

    init(collection status: SyncModel.Status, lastSynced: Date?) {
        self.lastSynced = lastSynced
        switch status {
        case .idle, .signingIn:
            kind = lastSynced == nil ? .notSynced : .synced
        case .syncing(let progress):
            kind = .syncing
            switch progress {
            case .connecting:
                break
            case .syncing(let detail):
                progressDetail = detail
            case .uploading(let transferred, let total), .downloading(let transferred, let total):
                if total > 0 { fraction = Double(min(transferred, total)) / Double(total) }
            }
        case .choosingDirection, .fullSyncRequested:
            kind = .oneWay
        case .synced:
            kind = .synced
        case .failed(let failure):
            kind = failure.reason == .cancelled ? .cancelled : .failed
            self.failure = failure
        }
    }
}
