import CollectionStore
import CollectionTesting
import Foundation
import Observation
import SyncFeature
import SyncTesting
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
    @Test("A single sync action transfers media in both directions after collection sync")
    func syncsMediaBothWays() async throws {
        let server = try await SyncServer(users: [("alice", "correct horse")])
        let (image, audio) = try await withTemporaryCollection { fixture in
            try await fixture.importFixture(.basicDeck)
            let folder = fixture.location.mediaFolder
            return (
                try Data(contentsOf: folder.appendingPathComponent("sol.png")),
                try Data(contentsOf: folder.appendingPathComponent("adios.m4a"))
            )
        }
        try await withTemporaryCollection { phone in
            try await phone.addBasicNotes(count: 1, toDeck: phone.addDeck(named: "Spanish"))
            try image.write(to: phone.location.mediaFolder.appendingPathComponent("sol.png"))
            let phoneSync = try await signedIn(phone, to: server)
            await phoneSync.sync()
            await phoneSync.upload()

            try await withTemporaryCollection { tablet in
                let tabletSync = try await signedIn(tablet, to: server)
                await tabletSync.sync()
                await tabletSync.download()
                let receivedImage = tablet.location.mediaFolder.appendingPathComponent("sol.png")
                #expect(try Data(contentsOf: receivedImage) == image)

                try audio.write(to: tablet.location.mediaFolder.appendingPathComponent("adios.m4a"))
                await tabletSync.sync()
                await phoneSync.sync()
                let receivedAudio = phone.location.mediaFolder.appendingPathComponent("adios.m4a")
                #expect(try Data(contentsOf: receivedAudio) == audio)
            }
        }
    }

    @Test("Media shows progress while the collection is usable, and Cancel lets it resume on retry")
    func cancelAndRetryMedia() async throws {
        let server = try await SyncServer(users: [("alice", "correct horse")])
        try await withTemporaryCollection { phone in
            try await phone.addBasicNotes(count: 1, toDeck: phone.addDeck(named: "Spanish"))
            let media = Data("a media transfer in progress".utf8)
            try media.write(to: phone.location.mediaFolder.appendingPathComponent("cancel-retry.png"))
            let model = try await signedIn(phone, to: server)
            await model.sync()

            pauseServerWhenMediaStarts(server, model: model)
            async let uploading: Void = model.upload()
            try await eventually(timeout: .seconds(15), "media progress to show while the server is paused") {
                if case .syncing(.some(let progress)) = model.mediaStatus { !progress.checked.isEmpty } else { false }
            }
            #expect(model.status == .synced(SyncOutcome(kind: .uploaded, serverMessage: nil)))
            #expect(try await phone.cardCount(matching: "deck:Spanish") == 1)

            model.cancel()
            await uploading
            #expect(model.mediaStatus == .cancelled)
            #expect(model.status == .synced(SyncOutcome(kind: .uploaded, serverMessage: nil)))

            server.resume()
            await model.retryMediaSync()
            #expect(model.mediaStatus == .synced)
            try await withTemporaryCollection { tablet in
                let other = try await signedIn(tablet, to: server)
                await other.sync()
                await other.download()
                let received = tablet.location.mediaFolder.appendingPathComponent("cancel-retry.png")
                #expect(try Data(contentsOf: received) == media)
            }
        }
    }

    @Test("A media-only failure leaves the collection synced and can be retried after reopening")
    func mediaFailureSurvivesRelaunch() async throws {
        let server = try await SyncServer(users: [("alice", "correct horse")])
        try await withTemporaryCollection { phone in
            try await phone.addBasicNotes(count: 1, toDeck: phone.addDeck(named: "Spanish"))
            let media = Data("a pending media file".utf8)
            try media.write(to: phone.location.mediaFolder.appendingPathComponent("pending.png"))
            let storage = MemoryAccountStorage()
            let model = try await signedIn(phone, to: server, storage: storage)
            await model.sync()

            pauseServerWhenMediaStarts(server, model: model)
            async let uploading: Void = model.upload()
            try await eventually(timeout: .seconds(15), "media progress before interrupting the server") {
                if case .syncing(.some) = model.mediaStatus { true } else { false }
            }
            let inProgress = try #require(storage.storedText)
            server.interrupt()
            await uploading

            let collectionOutcome = SyncModel.Status.synced(SyncOutcome(kind: .uploaded, serverMessage: nil))
            #expect(model.status == collectionOutcome)
            guard case .failed = model.mediaStatus else {
                Issue.record("Expected a media failure after the connection dropped, got \(model.mediaStatus)")
                return
            }

            try await phone.close()
            let reopened = try await CollectionStore.open(at: phone.location, core: phone.core)
            let afterTermination = SyncModel(store: reopened, storage: MemoryAccountStorage(storedText: inProgress))
            #expect(afterTermination.status == collectionOutcome)
            #expect(afterTermination.mediaStatus == .interrupted)

            let afterFailure = SyncModel(store: reopened, storage: storage)
            #expect(afterFailure.status == collectionOutcome)
            #expect(afterFailure.canRetryMediaSync)
            try await server.restart()
            await afterFailure.retryMediaSync()
            #expect(afterFailure.mediaStatus == .synced)
            #expect(SyncModel(store: reopened, storage: storage).mediaStatus == .synced)

            try await withTemporaryCollection { tablet in
                let other = try await signedIn(tablet, to: server)
                await other.sync()
                await other.download()
                let received = tablet.location.mediaFolder.appendingPathComponent("pending.png")
                #expect(try Data(contentsOf: received) == media)
            }
        }
    }

    @Test("A pending media retry stays with its sign-in, and a new destination reconciles the selected profile")
    func switchingMediaDestinations() async throws {
        let first = try await SyncServer(users: [("alice", "correct horse")])
        let second = try await SyncServer(users: [("alice", "second password")])
        try await withTemporaryCollection { phone in
            try await phone.addBasicNotes(count: 1, toDeck: phone.addDeck(named: "First"))
            let phoneMedia = phone.location.mediaFolder
            let original = Data("existing media on first".utf8)
            try original.write(to: phoneMedia.appendingPathComponent("original.png"))
            let pending = Data("pending media on first".utf8)
            let storage = MemoryAccountStorage()
            let model = try await signedIn(phone, to: first, storage: storage)
            let originalKey = try #require(model.account?.hostKey)
            await model.sync()
            await model.upload()
            #expect(model.mediaStatus == .synced)
            try pending.write(to: phoneMedia.appendingPathComponent("pending.png"))

            pauseServerWhenMediaStarts(first, model: model)
            let syncing = Task { await model.sync() }
            defer {
                syncing.cancel()
                first.resume()
            }
            try await eventually("the first profile's media to start") {
                if case .syncing = model.mediaStatus { true } else { false }
            }
            model.signOut()
            #expect(model.account?.hostKey == originalKey)

            try await withTemporaryCollection { tablet in
                try await tablet.addBasicNotes(count: 2, toDeck: tablet.addDeck(named: "Second"))
                let secondMedia = Data("existing media on second".utf8)
                try secondMedia.write(to: tablet.location.mediaFolder.appendingPathComponent("second.png"))
                let tabletSync = try await signedIn(tablet, to: second, password: "second password")
                await tabletSync.sync()
                await tabletSync.upload()
                #expect(tabletSync.mediaStatus == .synced)
                #expect(try tablet.mediaFileNames() == ["second.png"])

                model.cancel()
                await syncing.value
                first.resume()
                #expect(model.canRetryMediaSync)
                model.signOut()
                model.serverAddress = second.address
                model.userName = "alice"
                model.password = "second password"
                await model.signIn()
                #expect(model.account?.hostKey != originalKey)
                #expect(model.account?.server?.absoluteString == second.address)
                #expect(!model.canRetryMediaSync)
                await model.retryMediaSync()
                await tabletSync.sync()
                #expect(try tablet.mediaFileNames() == ["second.png"])

                // Start and confirm a new collection sync. Both servers began
                // with one media change, so their sequence numbers are equal
                // despite holding different files.
                await model.sync()
                #expect(model.status == .choosingDirection(.either))
                await model.download()
                #expect(model.mediaStatus == .synced)
                #expect(try Data(contentsOf: phoneMedia.appendingPathComponent("second.png")) == secondMedia)
                #expect(try Data(contentsOf: phoneMedia.appendingPathComponent("original.png")) == original)
                await tabletSync.sync()
                #expect(try tablet.mediaFileNames() == ["original.png", "pending.png", "second.png"])
            }
        }
    }

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

    @Test("Switching servers discards the old key, redirect and pending upload")
    func switchingServers() async throws {
        let first = try await SyncServer(users: [("alice", "correct horse")])
        let second = try await SyncServer(users: [("alice", "second password")])

        try await withTemporaryCollection { phone in
            try await phone.addBasicNotes(count: 1, toDeck: phone.addDeck(named: "Private"))
            let previous = try await signedIn(phone, to: first)
            let previousAccount = try #require(previous.account)
            let configuredAddress = try unreachableAddress()
            let storage = MemoryAccountStorage(storedText: """
                {
                    "server": "\(configuredAddress)",
                    "userName": "alice",
                    "hostKey": "\(previousAccount.hostKey)",
                    "redirectedEndpoint": "\(first.address)"
                }
                """)
            let model = SyncModel(store: phone, storage: storage)

            #expect(model.serverAddress == configuredAddress)
            await model.sync()
            #expect(model.status == .choosingDirection(.uploadOnly))
            #expect(model.account?.server?.absoluteString == configuredAddress)

            model.selectDestination(.ankiWeb)
            #expect(model.destination == .selfHosted, "Sign out before changing destinations")

            model.signOut()
            model.selectDestination(.ankiWeb)
            #expect(model.account == nil)
            #expect(storage.storedText == nil)
            #expect(model.status == .idle)
            model.selectDestination(.selfHosted)

            model.serverAddress = second.address
            model.userName = "alice"
            model.password = "second password"
            await model.signIn()
            let nextAccount = try #require(model.account)
            #expect(nextAccount.server?.absoluteString == second.address)
            #expect(nextAccount.hostKey != previousAccount.hostKey)

            // The previous server requested a full upload. On the new server,
            // the learner has not started a sync or been asked to upload.
            await model.upload()
            #expect(model.status == .idle)

            let observerStorage = MemoryAccountStorage(nextAccount)
            try await withTemporaryCollection { tablet in
                let observer = SyncModel(store: tablet, storage: observerStorage)
                await observer.sync()
                #expect(observer.status == .synced(SyncOutcome(kind: .merged, serverMessage: nil)))
                let count = try await tablet.cardCount(matching: "deck:Private")
                #expect(count == 0)
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
    private func signedIn(
        _ store: CollectionStore,
        to server: SyncServer,
        storage: MemoryAccountStorage = MemoryAccountStorage(),
        password: String = "correct horse"
    ) async throws -> SyncModel {
        let model = SyncModel(store: store, storage: storage)
        model.selectDestination(.selfHosted)
        model.serverAddress = server.address
        model.userName = "alice"
        model.password = password
        await model.signIn()
        try #require(model.account != nil, "sign-in failed: \(String(describing: model.status))")
        return model
    }

    /// Freeze only the local server once collection sync has returned and before
    /// media starts, so the media stage can be observed and cancelled reliably.
    private func pauseServerWhenMediaStarts(_ server: SyncServer, model: SyncModel) {
        let pid = server.processIdentifier
        withObservationTracking {
            _ = model.mediaStatus
        } onChange: {
            _ = Darwin.kill(pid, SIGSTOP)
        }
    }
}
