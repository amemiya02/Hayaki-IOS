import CollectionStore
import CollectionTesting
import Foundation
import SyncFeature
import Testing

/// Two or three devices, each a throwaway collection with its own core, syncing
/// through one real sync server.
@MainActor
@Suite(
    "Syncing the collection",
    .enabled(if: SyncServer.isBuilt, SyncServer.skipMessage),
    .timeLimit(.minutes(5))
)
struct SyncTests {
    @Test("The first sync to an empty server asks before uploading, then uploads")
    func firstSyncUploads() async throws {
        let server = try await SyncServer(users: [("alice", "correct horse")])
        try await withTemporaryCollection { phone in
            try await phone.addBasicNotes(count: 3, toDeck: phone.addDeck(named: "Spanish"))
            let model = try await signedIn(phone, to: server)

            await model.sync()

            // Nothing on the server to download: uploading is the only way,
            // and it still waits for the learner.
            #expect(model.status == .choosingDirection(.uploadOnly))

            await model.upload()

            #expect(model.status == .synced(SyncOutcome(kind: .uploaded, serverMessage: nil)))
            try await withTemporaryCollection { tablet in
                let other = try await signedIn(tablet, to: server)
                await other.sync()
                #expect(other.status == .choosingDirection(.downloadOnly))
                await other.download()
                #expect(other.status == .synced(SyncOutcome(kind: .downloaded, serverMessage: nil)))
                #expect(try await tablet.cardCount(matching: "deck:Spanish") == 3)
            }
        }
    }

    @Test("Once both devices have the collection, changes made on either reach the other")
    func normalSyncBothWays() async throws {
        let server = try await SyncServer(users: [("alice", "correct horse")])
        try await withTemporaryCollection { phone in
            let spanish = try await phone.addDeck(named: "Spanish")
            try await phone.addBasicNotes(count: 3, toDeck: spanish)
            let phoneSync = try await signedIn(phone, to: server)
            await phoneSync.sync()
            await phoneSync.upload()

            try await withTemporaryCollection { tablet in
                let tabletSync = try await signedIn(tablet, to: server)
                await tabletSync.sync()
                await tabletSync.download()

                // The tablet adds a deck and studies a card.
                try await tablet.addBasicNotes(count: 2, toDeck: tablet.addDeck(named: "French"))
                try await tablet.answerNextCard(inDeck: tablet.deckID(named: "Spanish"), rating: .good)
                await tabletSync.sync()
                #expect(tabletSync.status == .synced(SyncOutcome(kind: .merged, serverMessage: nil)))

                // The phone receives both, and the deck list is told.
                let changes = phone.changes()
                await phoneSync.sync()
                #expect(phoneSync.status == .synced(SyncOutcome(kind: .merged, serverMessage: nil)))
                #expect(try await phone.deckNames().contains("French"))
                #expect(try await phone.cardCount(matching: "deck:French") == 2)
                #expect(try await phone.reviewCount(matching: "deck:Spanish") == 1)
                var iterator = changes.makeAsyncIterator()
                let change = await iterator.next()
                #expect(change?.contains(.deck) == true)

                // And the other way.
                try await phone.addBasicNotes(count: 1, toDeck: spanish)
                await phoneSync.sync()
                await tabletSync.sync()
                #expect(try await tablet.cardCount(matching: "deck:Spanish") == 4)
            }
        }
    }

    @Test("When the two sides cannot be merged, nothing is overwritten until the learner chooses")
    func conflictWaitsForTheLearner() async throws {
        let server = try await SyncServer(users: [("alice", "correct horse")])
        try await withTemporaryCollection { phone in
            try await phone.addBasicNotes(count: 3, toDeck: phone.addDeck(named: "Spanish"))
            let phoneSync = try await signedIn(phone, to: server)
            await phoneSync.sync()
            await phoneSync.upload()

            // A tablet with a collection of its own, never synced.
            try await withTemporaryCollection { tablet in
                try await tablet.addBasicNotes(count: 2, toDeck: tablet.addDeck(named: "French"))
                let tabletSync = try await signedIn(tablet, to: server)

                await tabletSync.sync()

                #expect(tabletSync.status == .choosingDirection(.either))
                // Neither side has changed.
                #expect(try await tablet.cardCount(matching: "deck:French") == 2)
                #expect(try await tablet.cardCount(matching: "deck:Spanish") == 0)
                await phoneSync.sync()
                #expect(phoneSync.status == .synced(SyncOutcome(kind: .merged, serverMessage: nil)))
                #expect(try await phone.cardCount(matching: "deck:Spanish") == 3)

                // Choosing neither leaves both as they are.
                await tabletSync.sync()
                tabletSync.keepBoth()
                #expect(tabletSync.status == .idle)
                #expect(try await tablet.cardCount(matching: "deck:French") == 2)
            }
        }
    }

    @Test("Uploading replaces the server's collection, and downloading replaces this device's")
    func forcedUploadAndDownload() async throws {
        let server = try await SyncServer(users: [("alice", "correct horse")])
        try await withTemporaryCollection { phone in
            try await phone.addBasicNotes(count: 3, toDeck: phone.addDeck(named: "Spanish"))
            let phoneSync = try await signedIn(phone, to: server)
            await phoneSync.sync()
            await phoneSync.upload()

            try await withTemporaryCollection { tablet in
                try await tablet.addBasicNotes(count: 2, toDeck: tablet.addDeck(named: "French"))
                let tabletSync = try await signedIn(tablet, to: server)
                await tabletSync.sync()
                #expect(tabletSync.status == .choosingDirection(.either))

                // The tablet's collection replaces the server's.
                await tabletSync.upload()
                #expect(tabletSync.status == .synced(SyncOutcome(kind: .uploaded, serverMessage: nil)))
                #expect(try await tablet.cardCount(matching: "deck:French") == 2)

                // The phone can no longer merge, and downloads.
                let changes = phone.changes()
                await phoneSync.sync()
                #expect(phoneSync.status == .choosingDirection(.either))
                #expect(try await phone.cardCount(matching: "deck:Spanish") == 3)
                await phoneSync.download()
                #expect(phoneSync.status == .synced(SyncOutcome(kind: .downloaded, serverMessage: nil)))
                #expect(try await phone.cardCount(matching: "deck:French") == 2)
                #expect(try await phone.cardCount(matching: "deck:Spanish") == 0)
                var iterator = changes.makeAsyncIterator()
                #expect(await iterator.next() == .everything)
            }
        }
    }

    @Test("Cancelling a sync stops it, keeps this device's collection as it was, and a later sync completes")
    func cancelSync() async throws {
        let server = try await SyncServer(users: [("alice", "correct horse")])
        try await withTemporaryCollection { phone in
            let spanish = try await phone.addDeck(named: "Spanish")
            try await phone.addBasicNotes(count: 1, toDeck: spanish)
            let phoneSync = try await signedIn(phone, to: server)
            await phoneSync.sync()
            await phoneSync.upload()
            // Enough changes that sending them takes a while.
            try await phone.addNotes(ofType: "Basic", fields: (0..<20_000).map { ["Question \($0)", "Answer \($0)"] }, toDeck: spanish)

            async let syncing: Void = phoneSync.sync()
            try await eventually(timeout: .seconds(60), "the sync to report its progress") {
                if case .syncing(.syncing) = phoneSync.status { true } else { false }
            }
            phoneSync.cancel()
            await syncing

            #expect(phoneSync.status.failure?.reason == .cancelled)
            #expect(try await phone.cardCount(matching: "deck:Spanish") == 20_001)

            // Nothing half-sent is left behind: the next sync sends everything.
            await phoneSync.sync()
            #expect(phoneSync.status == .synced(SyncOutcome(kind: .merged, serverMessage: nil)))
            try await withTemporaryCollection { tablet in
                let tabletSync = try await signedIn(tablet, to: server)
                await tabletSync.sync()
                await tabletSync.download()
                #expect(try await tablet.cardCount(matching: "deck:Spanish") == 20_001)
            }
        }
    }

    @Test("A key the server no longer accepts is reported, with a way out")
    func keyNoLongerAccepted() async throws {
        let server = try await SyncServer(users: [("alice", "correct horse")])
        try await withTemporaryCollection { phone in
            let account = SyncAccount(server: URL(string: server.address)!, userName: "alice", hostKey: "not-a-key")
            let model = SyncModel(store: phone, storage: MemoryAccountStorage(account))

            await model.sync()

            let failure = try #require(model.status.failure)
            #expect(failure.reason == .wrongCredentials)
            #expect(failure.message == "The server no longer accepts this device's sign-in. Sign out, then sign in again.")
        }
    }

    @Test("A server that has gone away is reported with the cause")
    func serverGone() async throws {
        let address = try unreachableAddress()
        try await withTemporaryCollection { phone in
            let account = SyncAccount(server: URL(string: address)!, userName: "alice", hostKey: "key")
            let model = SyncModel(store: phone, storage: MemoryAccountStorage(account))

            await model.sync()

            let failure = try #require(model.status.failure)
            #expect(failure.reason == .unreachable)
            #expect(failure.detail?.contains("error sending request") == true)
        }
    }

    @Test("Requests name the client as Hayaki on this system, never as another client")
    func clientIdentity() async throws {
        let server = try await SyncServer(users: [("alice", "correct horse")])
        try await withTemporaryCollection { phone in
            let model = try await signedIn(phone, to: server)
            await model.sync()

            // The platform the core reports when a sync begins.
            let platform = try #require(ProcessInfo.processInfo.environment["PLATFORM"])
            #expect(platform.hasPrefix("hayaki:"))
            #expect(platform.contains(":macos:"))
            // Every request carries the core's build, named as Hayaki's; the
            // server logs it for each request.
            let clients = server.log.split(separator: "\n").compactMap { line in
                line.firstMatch(of: /client="?([^" }]+)/).map { String($0.1) }
            }
            #expect(!clients.isEmpty)
            for client in clients {
                #expect(client.contains(",hayaki-"), "\(client)")
                #expect(client.hasSuffix(",macos"), "\(client)")
            }
        }
    }

    /// A sync model for `store`, signed in to `server` as alice.
    private func signedIn(_ store: CollectionStore, to server: SyncServer) async throws -> SyncModel {
        let model = SyncModel(store: store, storage: MemoryAccountStorage())
        model.serverAddress = server.address
        model.userName = "alice"
        model.password = "correct horse"
        await model.signIn()
        try #require(model.account != nil, "sign-in failed: \(String(describing: model.status))")
        return model
    }
}
