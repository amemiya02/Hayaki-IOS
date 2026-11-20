import Foundation

/// The media transfer has its own result because collection sync finishes first.
public enum MediaSyncStatus: Equatable, Sendable {
    case idle
    case syncing(MediaSyncProgress?)
    case synced
    case cancelled
    /// The media transfer stopped before completion without a manual cancellation.
    case interrupted
    /// The live failure includes the core's explanation. Across launches,
    /// only the outcome is kept.
    case failed(SyncFailure?)
}

/// The core's localized counts of checked, added and removed files.
public struct MediaSyncProgress: Equatable, Sendable {
    public let checked: String
    public let added: String
    public let removed: String
}

/// The current attempt's timing, kept separately from the last successful sync.
struct MediaSyncTiming {
    let startedAt: Date
    var lastProgressAt: Date?
}

/// Saved with one sign-in so a retry can only use the original destination.
struct SavedMediaSync: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case transferring, synced, cancelled, interrupted, failed
    }

    let phase: Phase
    let collection: SyncOutcome

    var status: MediaSyncStatus {
        switch phase {
        case .transferring, .interrupted: .interrupted
        case .synced: .synced
        case .cancelled: .cancelled
        case .failed: .failed(nil)
        }
    }
}
