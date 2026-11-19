/// The media transfer has its own result because collection sync finishes first.
public enum MediaSyncStatus: Equatable, Sendable {
    case idle
    case syncing(MediaSyncProgress?)
    case synced
    case cancelled
    /// The previous launch ended before Anki reported whether media finished.
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

/// Saved with one sign-in so a retry can only use the original destination.
struct SavedMediaSync: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case transferring, synced, cancelled, failed
    }

    let phase: Phase
    let collection: SyncOutcome

    var status: MediaSyncStatus {
        switch phase {
        case .transferring: .interrupted
        case .synced: .synced
        case .cancelled: .cancelled
        case .failed: .failed(nil)
        }
    }
}
