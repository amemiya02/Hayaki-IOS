/// The media transfer has its own result because collection sync finishes first.
public enum MediaSyncStatus: Equatable, Sendable {
    case idle
    case syncing(MediaSyncProgress?)
    case synced
    case cancelled
    case failed(SyncFailure)
}

/// The core's localized counts of checked, added and removed files.
public struct MediaSyncProgress: Equatable, Sendable {
    public let checked: String
    public let added: String
    public let removed: String
}
