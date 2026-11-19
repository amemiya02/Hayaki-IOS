import CollectionStore
import CollectionTesting
import Foundation
import SyncFeature
import SyncTesting
import Testing

@MainActor
@Suite("Sync policies", .enabled(if: SyncServer.isBuilt, SyncServer.skipMessage))
struct SyncPolicyTests {
    @Test("Metered collection sync needs consent and respects the independent media preference")
    func meteredSyncAndMedia() async throws {
        let server = try await SyncServer(users: [("alice", "correct horse")])
        try await withTemporaryCollection { local in
            let model = SyncModel(store: local, storage: MemoryAccountStorage(), network: { .metered })
            model.selectDestination(.selfHosted)
            model.serverAddress = server.address
            model.userName = "alice"
            model.password = "correct horse"
            await model.signIn()
            try #require(model.account != nil)
            let deck = try await local.addDeck(named: "Metered")
            try await local.addBasicNotes(count: 1, toDeck: deck)
            _ = try await local.addMediaFile(named: "metered.png", data: Data("media".utf8))
            model.policy.media = .onlyUnmetered

            await model.sync()
            #expect(model.needsMeteredConfirmation)
            #expect(model.status == .idle)

            model.dismissMeteredConfirmation()
            #expect(!model.needsMeteredConfirmation)
            await model.sync()
            await model.confirmMeteredSync(alwaysAllow: false)
            #expect(model.status == .choosingDirection(.uploadOnly))
            await model.upload()
            #expect(model.status == .synced(SyncOutcome(kind: .uploaded, serverMessage: nil)))
            #expect(model.mediaStatus == .idle)
            #expect(!model.policy.allowsMetered)

            await model.sync()
            #expect(model.needsMeteredConfirmation)
        }
    }
}
