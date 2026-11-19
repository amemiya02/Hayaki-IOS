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
            await model.confirmMeteredSync(alwaysAllow: true)
            #expect(model.policy.allowsMetered)
            #expect(!model.needsMeteredConfirmation)
            #expect(model.mediaStatus == .idle)
        }
    }

    @Test("Automatic sync respects the foreground attempt interval and transfers on background")
    func automaticSyncAndBadge() async throws {
        let server = try await SyncServer(users: [("alice", "correct horse")])
        try await withTemporaryCollection { local in
            var now = Date(timeIntervalSince1970: 10_000)
            var network = SyncNetwork.unmetered
            let model = SyncModel(
                store: local, storage: MemoryAccountStorage(),
                network: { network }, now: { now }
            )
            #expect(model.badge == .signedOut)
            model.selectDestination(.selfHosted)
            model.serverAddress = server.address
            model.userName = "alice"
            model.password = "correct horse"
            await model.signIn()
            try #require(model.account != nil)
            let deck = try await local.addDeck(named: "Automatic")
            try await local.addBasicNotes(count: 1, toDeck: deck)
            model.policy.media = .never

            await model.automaticSync(.foreground)
            #expect(model.status == .idle)
            await model.sync()
            #expect(model.badge == .oneWay)
            await model.upload()

            model.policy.automatic = true
            try await local.addBasicNotes(count: 1, toDeck: deck)
            await model.refreshBadge()
            #expect(model.badge == .pendingChanges)
            model.policy.showsStatusBadge = false
            #expect(model.badge == nil)
            model.policy.showsStatusBadge = true

            await model.automaticSync(.foreground)
            #expect(model.badge == .pendingChanges)
            network = .metered
            now.addTimeInterval(601)
            await model.automaticSync(.foreground)
            #expect(model.badge == .pendingChanges)
            #expect(!model.needsMeteredConfirmation)

            network = .unmetered
            await model.automaticSync(.foreground)
            #expect(model.badge == nil)
            try await local.addBasicNotes(count: 1, toDeck: deck)
            await model.automaticSync(.background)
            #expect(model.status == .synced(SyncOutcome(kind: .merged, serverMessage: nil)))
            #expect(model.mediaStatus == .idle)

            let media = Data("background media".utf8)
            _ = try await local.addMediaFile(named: "automatic.png", data: media)
            model.policy.media = .always
            await model.automaticSync(.background)
            #expect(model.mediaStatus == .synced)

            try await withTemporaryCollection { other in
                let reader = SyncModel(store: other, storage: MemoryAccountStorage(), network: { .unmetered })
                reader.selectDestination(.selfHosted)
                reader.serverAddress = server.address
                reader.userName = "alice"
                reader.password = "correct horse"
                await reader.signIn()
                await reader.sync()
                await reader.download()
                let count = try await other.cardCount(matching: "deck:Automatic")
                #expect(count == 3)
                let received = try Data(contentsOf: other.location.mediaFolder.appendingPathComponent("automatic.png"))
                #expect(received == media)
            }
        }
    }

    @Test("A self-hosted TLS certificate stays with its signed-in destination across relaunch")
    func customCertificate() async throws {
        let server = try await SyncServer(users: [("alice", "correct horse")])
        let tls = try await LocalSyncTLS(for: server)
        try await withTemporaryCollection { local in
            let storage = MemoryAccountStorage()
            let model = SyncModel(store: local, storage: storage, network: { .unmetered })
            model.selectDestination(.selfHosted)
            model.serverAddress = tls.address
            model.userName = "alice"
            model.password = "correct horse"
            await model.signIn()
            #expect(model.status.failure?.reason == .unreachable)

            let invalid = await model.updateCustomCertificate("This is not PEM")
            #expect(invalid?.reason == .invalidCertificate)
            let result = await model.updateCustomCertificate(tls.certificate)
            #expect(result == nil)
            await model.signIn()
            let account = try #require(model.account)

            let relaunched = SyncModel(store: local, storage: storage, network: { .unmetered })
            #expect(relaunched.customCertificate == tls.certificate.trimmingCharacters(in: .whitespacesAndNewlines))
            let deck = try await local.addDeck(named: "TLS")
            try await local.addBasicNotes(count: 1, toDeck: deck)
            _ = try await local.addMediaFile(named: "tls.png", data: Data("TLS media".utf8))
            await relaunched.sync()
            await relaunched.upload()
            #expect(relaunched.mediaStatus == .synced)

            relaunched.beginDestinationChange()
            relaunched.serverAddress = tls.address.replacingOccurrences(of: "127.0.0.1", with: "localhost")
            relaunched.userName = "alice"
            relaunched.password = "correct horse"
            await relaunched.signIn()
            #expect(relaunched.status.failure?.reason == .unreachable)
            #expect(relaunched.account?.server == account.server)
            relaunched.cancelDestinationChange()
            #expect(!relaunched.customCertificate.isEmpty)

            let removed = await relaunched.updateCustomCertificate("")
            #expect(removed == nil)
            #expect(relaunched.customCertificate.isEmpty)
            await relaunched.sync()
            #expect(relaunched.status.failure?.reason == .unreachable)
        }
    }

    @Test("Automatic sync checks the collection at a newly signed-in destination")
    func automaticSyncAfterDestinationChange() async throws {
        let original = try await SyncServer(users: [("alice", "correct horse")])
        let replacement = try await SyncServer(users: [("alice", "correct horse")])
        try await withTemporaryCollection { local in
            let model = SyncModel(store: local, storage: MemoryAccountStorage(), network: { .unmetered })
            model.selectDestination(.selfHosted)
            model.serverAddress = original.address
            model.userName = "alice"
            model.password = "correct horse"
            await model.signIn()
            try #require(model.account != nil)
            let deck = try await local.addDeck(named: "Conflict")
            try await local.addBasicNotes(count: 1, toDeck: deck)
            await model.sync()
            await model.upload()
            #expect(model.mediaStatus == .synced)

            model.beginDestinationChange()
            model.serverAddress = replacement.address
            model.userName = "alice"
            model.password = "correct horse"
            await model.signIn()
            try #require(model.serverAddress == replacement.address)
            model.policy.automatic = true
            await model.automaticSync(.foreground)
            #expect(model.status == .choosingDirection(.uploadOnly))
            #expect(model.mediaStatus == .idle)
        }
    }

    @Test("Decks can read the collection while the sync badge waits for the server")
    func badgeDoesNotBlockCollection() async throws {
        let server = try await SyncServer(users: [("alice", "correct horse")])
        try await withTemporaryCollection { local in
            let model = SyncModel(store: local, storage: MemoryAccountStorage(), network: { .unmetered })
            model.selectDestination(.selfHosted)
            model.serverAddress = server.address
            model.userName = "alice"
            model.password = "correct horse"
            await model.signIn()
            try #require(model.account != nil)

            _ = Darwin.kill(server.processIdentifier, SIGSTOP)
            defer { server.resume() }
            async let badge: Void = model.refreshBadge()
            try await eventually("the badge check to begin") { model.isBusy }
            let resume = Task {
                try await Task.sleep(for: .seconds(1))
                server.resume()
            }
            let clock = ContinuousClock()
            let started = clock.now
            let decks = try await local.deckNames()
            let elapsed = clock.now - started
            #expect(decks == ["Default"])
            #expect(elapsed < .milliseconds(850))
            try await resume.value
            await badge
        }
    }

    @Test("A configured collection timeout is honored by the upstream core", .timeLimit(.minutes(2)))
    func collectionTimeout() async throws {
        let server = try await SyncServer(users: [("alice", "correct horse")])
        try await withTemporaryCollection { local in
            let model = SyncModel(store: local, storage: MemoryAccountStorage(), network: { .unmetered })
            model.selectDestination(.selfHosted)
            model.serverAddress = server.address
            model.userName = "alice"
            model.password = "correct horse"
            await model.signIn()
            try #require(model.account != nil)
            model.policy.setTimeoutSeconds(36)

            _ = Darwin.kill(server.processIdentifier, SIGSTOP)
            defer { server.resume() }
            let clock = ContinuousClock()
            let start = clock.now
            await model.sync()
            let elapsed = clock.now - start
            #expect(model.status.failure?.reason == .unreachable)
            #expect(elapsed >= .seconds(35))
            #expect(elapsed < .seconds(50))
        }
    }
}
