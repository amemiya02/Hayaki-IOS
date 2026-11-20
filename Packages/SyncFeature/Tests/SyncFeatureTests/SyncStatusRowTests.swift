import Foundation
@testable import SyncFeature
import Testing

/// What the collection and media rows on the Sync screen show for each state.
@MainActor
@Suite("Sync status rows")
struct SyncStatusRowTests {
    private let progress = MediaSyncProgress(checked: "Checked: 12", added: "Added: 3↑ 1↓", removed: "Removed: 0↑ 0↓")
    private let failure = SyncFailure(reason: .unreachable, message: "Could not reach the server.", detail: "timed out")

    @Test("Every media state has its own icon and status text")
    func mediaStatesAreDistinct() {
        let states: [MediaSyncStatus] = [
            .idle, .syncing(nil), .synced, .cancelled, .interrupted, .failed(nil),
        ]
        let rows = states.map { SyncStatusRow(media: $0, lastSynced: nil) }
        #expect(Set(rows.map(\.status)).count == states.count)
        #expect(Set(rows.map(\.systemImage)).count == states.count)
    }

    @Test("Media progress counts appear inline in the row while media syncs")
    func mediaProgressIsInline() {
        let row = SyncStatusRow(media: .syncing(progress), lastSynced: nil)
        #expect(row.isRunning)
        #expect(row.progressDetail == "Checked: 12 · Added: 3↑ 1↓ · Removed: 0↑ 0↓")
        #expect(SyncStatusRow(media: .syncing(nil), lastSynced: nil).progressDetail == nil)
        #expect(!SyncStatusRow(media: .synced, lastSynced: nil).isRunning)
    }

    @Test("A media failure carries its reason for the row below; a failure from a previous launch has none")
    func mediaFailureReason() {
        #expect(SyncStatusRow(media: .failed(failure), lastSynced: nil).failure == failure)
        #expect(SyncStatusRow(media: .failed(nil), lastSynced: nil).failure == nil)
        #expect(SyncStatusRow(media: .failed(nil), lastSynced: nil).isFailed)
        #expect(!SyncStatusRow(media: .interrupted, lastSynced: nil).isFailed)
    }

    @Test("The collection row shows determinate progress for uploads and downloads with a known size")
    func collectionProgress() {
        #expect(SyncStatusRow(collection: .syncing(.uploading(transferred: 25, total: 100)), lastSynced: nil).fraction == 0.25)
        #expect(SyncStatusRow(collection: .syncing(.downloading(transferred: 200, total: 100)), lastSynced: nil).fraction == 1)
        #expect(SyncStatusRow(collection: .syncing(.uploading(transferred: 0, total: 0)), lastSynced: nil).fraction == nil)
        let exchanging = SyncStatusRow(collection: .syncing(.syncing(detail: "Added/modified: 3↑ 0↓")), lastSynced: nil)
        #expect(exchanging.isRunning)
        #expect(exchanging.fraction == nil)
        #expect(exchanging.progressDetail == "Added/modified: 3↑ 0↓")
    }

    @Test("The collection row is synced after a sync, and before one only when an earlier sync is known")
    func collectionSynced() {
        let earlier = Date(timeIntervalSince1970: 1_000)
        let synced = SyncStatusRow(collection: .synced(SyncOutcome(kind: .merged, serverMessage: nil)), lastSynced: earlier)
        #expect(synced.status == SyncStatusRow(collection: .idle, lastSynced: earlier).status)
        #expect(synced.lastSynced == earlier)
        #expect(synced.status != SyncStatusRow(collection: .idle, lastSynced: nil).status)
    }

    @Test("A collection failure keeps its reason, and a cancelled sync reads as interrupted, not failed")
    func collectionFailure() {
        let failed = SyncStatusRow(collection: .failed(failure), lastSynced: nil)
        #expect(failed.isFailed)
        #expect(failed.failure == failure)
        let cancelled = SyncStatusRow(collection: .failed(SyncFailure(reason: .cancelled)), lastSynced: nil)
        #expect(!cancelled.isFailed)
        #expect(cancelled.systemImage == SyncStatusRow(media: .cancelled, lastSynced: nil).systemImage)
        #expect(cancelled.failure?.reason == .cancelled)
    }
}
