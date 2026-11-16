import CollectionTesting
import Foundation
import SyncFeature
import Testing

@MainActor
@Suite("Signing in to a sync server", .timeLimit(.minutes(2)))
struct SignInTests {
    @Test("Without sync set up, nothing is configured and nothing asks for it")
    func notSetUp() async throws {
        try await withTemporaryCollection { store in
            let model = SyncModel(store: store, storage: MemoryAccountStorage())

            #expect(model.account == nil)
            #expect(model.status == .idle)
            // No server is suggested: the learner types their own.
            #expect(model.serverAddress.isEmpty)
            #expect(!model.canSignIn)
        }
    }

    @Test("Signing in needs a server address, a user name and a password")
    func everyFieldIsRequired() async throws {
        try await withTemporaryCollection { store in
            let model = SyncModel(store: store, storage: MemoryAccountStorage())
            model.userName = "alice"
            model.password = "correct horse"
            #expect(!model.canSignIn)

            model.serverAddress = "https://sync.example.org/"
            #expect(model.canSignIn)

            model.password = ""
            #expect(!model.canSignIn)
        }
    }

    @Test("An address that is not a web address is refused before anything is sent")
    func addressMustBeAWebAddress() async throws {
        try await withTemporaryCollection { store in
            let storage = MemoryAccountStorage()
            let model = SyncModel(store: store, storage: storage)
            model.serverAddress = "sync.example.org"
            model.userName = "alice"
            model.password = "correct horse"

            await model.signIn()

            #expect(model.status.failure?.reason == .invalidAddress)
            #expect(model.account == nil)
            #expect(storage.storedText == nil)
        }
    }

    @Test("Signing in keeps the key the server issued, never the password", .enabled(if: SyncServer.isBuilt, SyncServer.skipMessage))
    func signInKeepsOnlyTheKey() async throws {
        let server = try await SyncServer(users: [("alice", "correct horse")])
        try await withTemporaryCollection { store in
            let storage = MemoryAccountStorage()
            let model = SyncModel(store: store, storage: storage)
            model.serverAddress = server.address
            model.userName = "alice"
            model.password = "correct horse"

            await model.signIn()

            #expect(model.status == .idle)
            let account = try #require(model.account)
            #expect(account.userName == "alice")
            #expect(account.server.absoluteString == server.address)
            #expect(!account.hostKey.isEmpty)
            #expect(try storage.load() == account)
            let stored = try #require(storage.storedText)
            #expect(!stored.contains("correct horse"))
            // The password field is cleared too.
            #expect(model.password.isEmpty)
        }
    }

    @Test("A learner who signed in earlier is still signed in")
    func signedInEarlier() async throws {
        try await withTemporaryCollection { store in
            let account = SyncAccount(server: URL(string: "https://sync.example.org/")!, userName: "alice", hostKey: "key")
            let model = SyncModel(store: store, storage: MemoryAccountStorage(account))

            #expect(model.account == account)
        }
    }

    @Test("Signing out removes the stored key")
    func signOut() async throws {
        try await withTemporaryCollection { store in
            let account = SyncAccount(server: URL(string: "https://sync.example.org/")!, userName: "alice", hostKey: "key")
            let storage = MemoryAccountStorage(account)
            let model = SyncModel(store: store, storage: storage)

            model.signOut()

            #expect(model.account == nil)
            #expect(storage.storedText == nil)
            #expect(model.status == .idle)
        }
    }

    @Test("A wrong password is reported as such, and nothing is stored", .enabled(if: SyncServer.isBuilt, SyncServer.skipMessage))
    func wrongPassword() async throws {
        let server = try await SyncServer(users: [("alice", "correct horse")])
        try await withTemporaryCollection { store in
            let storage = MemoryAccountStorage()
            let model = SyncModel(store: store, storage: storage)
            model.serverAddress = server.address
            model.userName = "alice"
            model.password = "battery staple"

            await model.signIn()

            let failure = try #require(model.status.failure)
            #expect(failure.reason == .wrongCredentials)
            #expect(failure.message == "The server did not accept this user name and password.")
            #expect(model.account == nil)
            #expect(storage.storedText == nil)
        }
    }

    @Test("An unreachable server is reported with the cause")
    func unreachableServer() async throws {
        let address = try unreachableAddress()
        try await withTemporaryCollection { store in
            let model = SyncModel(store: store, storage: MemoryAccountStorage())
            model.serverAddress = address
            model.userName = "alice"
            model.password = "correct horse"

            await model.signIn()

            let failure = try #require(model.status.failure)
            #expect(failure.reason == .unreachable)
            #expect(failure.message.contains("127.0.0.1"))
            // The core's own description of what went wrong, naming the request.
            let detail = try #require(failure.detail)
            #expect(detail.contains("error sending request"))
            #expect(model.account == nil)
        }
    }

    @Test("Signing in to a server that never answers can be cancelled")
    func cancelSignIn() async throws {
        let hungServer = try ListeningSocket()
        try await withTemporaryCollection { store in
            let model = SyncModel(store: store, storage: MemoryAccountStorage())
            model.serverAddress = hungServer.address
            model.userName = "alice"
            model.password = "correct horse"

            let clock = ContinuousClock()
            let started = clock.now
            async let signingIn: Void = model.signIn()
            try await eventually("signing in to begin") { model.status == .signingIn }
            try await Task.sleep(for: .milliseconds(500))
            model.cancel()
            await signingIn

            #expect(model.status.failure?.reason == .cancelled)
            #expect(model.account == nil)
            // Stopped by the cancel, long before the core's network timeout.
            #expect(clock.now - started < .seconds(10))
        }
    }
}
