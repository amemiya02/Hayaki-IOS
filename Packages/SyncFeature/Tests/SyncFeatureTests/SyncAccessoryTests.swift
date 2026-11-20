import Foundation
@testable import SyncFeature
import Testing

/// What the glass strip above the tab bar shows as a sync runs and ends.
@MainActor
@Suite("Sync accessory")
struct SyncAccessoryTests {
    private let merged = SyncOutcome(kind: .merged, serverMessage: nil)
    private let unreachable = SyncFailure(reason: .unreachable, message: "Could not reach the server.", detail: nil)
    private let media = MediaSyncProgress(checked: "Checked: 120", added: "Added: 8↑ 0↓", removed: "Removed: 0↑ 0↓")

    private func next(
        after previous: SyncAccessory?,
        _ status: SyncModel.Status,
        _ mediaStatus: MediaSyncStatus = .idle
    ) -> SyncAccessory? {
        SyncAccessory.next(after: previous, status: status, mediaStatus: mediaStatus)
    }

    @Test("Nothing shows when no sync has run, including a sync result restored at launch")
    func hiddenWithoutARunningSync() {
        #expect(next(after: nil, .idle) == nil)
        #expect(next(after: nil, .signingIn) == nil)
        #expect(next(after: nil, .synced(merged), .synced) == nil)
        #expect(next(after: nil, .failed(unreachable)) == nil)
        #expect(next(after: nil, .synced(merged), .failed(nil)) == nil)
        #expect(next(after: nil, .choosingDirection(.either)) == nil)
    }

    @Test("A collection sync shows its progress, with a fraction once the transfer size is known")
    func collectionProgress() {
        guard case .running(let connecting) = next(after: nil, .syncing(.connecting)) else {
            Issue.record("Expected a running strip"); return
        }
        #expect(connecting.fraction == nil)

        guard case .running(let upload) = next(after: nil, .syncing(.uploading(transferred: 30, total: 120))) else {
            Issue.record("Expected a running strip"); return
        }
        #expect(upload.fraction == 0.25)

        guard case .running(let exchanging) = next(after: nil, .syncing(.syncing(detail: "Added/modified: 3↑ 0↓"))) else {
            Issue.record("Expected a running strip"); return
        }
        #expect(exchanging.line.contains("Added/modified: 3↑ 0↓"))
    }

    @Test("A media transfer shows the core's counts on one line, after the collection finished")
    func mediaProgress() {
        guard case .running(let progress) = next(after: nil, .synced(merged), .syncing(media)) else {
            Issue.record("Expected a running strip"); return
        }
        #expect(progress.line.hasSuffix("Checked: 120 · Added: 8↑ 0↓ · Removed: 0↑ 0↓"))
        #expect(progress.fraction == nil)
    }

    @Test("A finished sync shows success, and a failed one keeps its reason and what Retry repeats")
    func outcomes() {
        let running = next(after: nil, .syncing(.connecting))
        #expect(next(after: running, .synced(merged), .synced) == .succeeded)
        #expect(next(after: running, .synced(merged), .idle) == .succeeded)
        #expect(next(after: running, .failed(unreachable)) == .failed(unreachable, retry: .collection))
        let mediaFailure = SyncFailure(reason: .other, message: "The sync failed.", detail: nil)
        #expect(next(after: running, .synced(merged), .failed(mediaFailure)) == .failed(mediaFailure, retry: .media))
        guard case .failed(let generic, retry: .media) = next(after: running, .synced(merged), .failed(nil)) else {
            Issue.record("Expected a media failure"); return
        }
        #expect(generic.reason == .other)
    }

    @Test("Cancelling, or a sync that needs a one-way choice, hides the strip")
    func cancelledOrOneWayHides() {
        let running = next(after: nil, .syncing(.connecting))
        #expect(next(after: running, .failed(SyncFailure(reason: .cancelled))) == nil)
        #expect(next(after: running, .synced(merged), .cancelled) == nil)
        #expect(next(after: running, .choosingDirection(.either)) == nil)
    }

    @Test("Success and failure stay until replaced; a failure clears when the sync state is reset")
    func persistence() {
        let failed = SyncAccessory.failed(unreachable, retry: .collection)
        #expect(next(after: failed, .failed(unreachable)) == failed)
        #expect(next(after: failed, .idle) == nil)
        #expect(next(after: .succeeded, .synced(merged), .synced) == .succeeded)
        guard case .running = next(after: failed, .syncing(.connecting)) else {
            Issue.record("Retry should show progress again"); return
        }
    }
}
