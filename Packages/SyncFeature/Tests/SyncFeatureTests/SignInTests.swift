import CollectionTesting
import Foundation
import SyncFeature
import SyncTesting
import Testing

@MainActor
@Suite("Signing in to a sync server", .timeLimit(.minutes(2)))
struct SignInTests {
    @Test("AnkiWeb is selected for a new collection")
    func notSetUp() async throws {
        try await withTemporaryCollection { store in
            let model = SyncModel(store: store, storage: MemoryAccountStorage())

            #expect(model.account == nil)
            #expect(model.status == .idle)
            #expect(model.destination == .ankiWeb)
            #expect(!model.canSignIn)
        }
    }

    @Test("A new collection can sign in to AnkiWeb with a user name and password")
    func ankiWebNeedsOnlyCredentials() async throws {
        try await withTemporaryCollection { store in
            let model = SyncModel(store: store, storage: MemoryAccountStorage())
            model.userName = "alice"
            model.password = "correct horse"
            #expect(model.serverAddress.isEmpty)
            #expect(model.canSignIn)

            model.password = ""
            #expect(!model.canSignIn)
        }
    }

    @Test("Changing destinations or self-hosted addresses clears credentials")
    func changingDestinationClearsCredentials() async throws {
        try await withTemporaryCollection { store in
            let model = SyncModel(store: store, storage: MemoryAccountStorage())
            model.userName = "ankiweb-user"
            model.password = "ankiweb-password"

            model.selectDestination(.selfHosted)

            #expect(model.userName.isEmpty)
            #expect(model.password.isEmpty)
            model.userName = "alice"
            model.password = "self-hosted-password"
            #expect(!model.canSignIn, "Self-hosted sign-in needs a server address")

            model.serverAddress = "https://sync.example.org/"

            #expect(model.userName.isEmpty)
            #expect(model.password.isEmpty)
            #expect(!model.canSignIn)
        }
    }

    @Test("An address that is not a web address is refused before anything is sent")
    func addressMustBeAWebAddress() async throws {
        try await withTemporaryCollection { store in
            let storage = MemoryAccountStorage()
            let model = SyncModel(store: store, storage: storage)
            model.selectDestination(.selfHosted)
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
            model.selectDestination(.selfHosted)
            model.serverAddress = server.address
            model.userName = "alice"
            model.password = "correct horse"

            await model.signIn()

            #expect(model.status == .idle)
            let account = try #require(model.account)
            #expect(account.userName == "alice")
            #expect(account.server?.absoluteString == server.address)
            #expect(!account.hostKey.isEmpty)
            #expect(try storage.load() == account)
            let stored = try #require(storage.storedText)
            #expect(!stored.contains("correct horse"))
            // The password field is cleared too.
            #expect(model.password.isEmpty)
        }
    }

    @Test("A Keychain item from a previous release keeps its self-hosted server")
    func signedInEarlier() async throws {
        try await withTemporaryCollection { store in
            let storage = MemoryAccountStorage(storedText: """
                {"server":"https://sync.example.org/","userName":"alice","hostKey":"key"}
                """)
            let model = SyncModel(store: store, storage: storage)

            #expect(model.destination == .selfHosted)
            #expect(model.serverAddress == "https://sync.example.org/")
            #expect(model.account?.userName == "alice")
            #expect(model.account?.hostKey == "key")
        }
    }

    @Test("A saved AnkiWeb sign-in restores the default destination")
    func restoreAnkiWebSignIn() async throws {
        try await withTemporaryCollection { store in
            let account = SyncAccount(server: nil, userName: "alice", hostKey: "key")
            let model = SyncModel(store: store, storage: MemoryAccountStorage(account))

            #expect(model.destination == .ankiWeb)
            #expect(model.account == account)
        }
    }

    @Test("A malformed Keychain item cannot turn a saved key into an AnkiWeb sign-in")
    func missingDestination() async throws {
        try await withTemporaryCollection { store in
            let storage = MemoryAccountStorage(storedText: """
                {"userName":"alice","hostKey":"key"}
                """)
            let model = SyncModel(store: store, storage: storage)

            #expect(model.status.failure?.reason == .secureStorage)
            #expect(model.account == nil)
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
            model.selectDestination(.selfHosted)
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

    @Test("Changing a server keeps the previous sign-in until the replacement succeeds",
          .enabled(if: SyncServer.isBuilt, SyncServer.skipMessage))
    func changingServerKeepsPreviousSignIn() async throws {
        let first = try await SyncServer(users: [("alice", "first password")])
        let second = try await SyncServer(users: [("sam", "second password")])
        try await withTemporaryCollection { store in
            let storage = MemoryAccountStorage()
            let model = SyncModel(store: store, storage: storage)
            model.selectDestination(.selfHosted)
            model.serverAddress = first.address
            model.userName = "alice"
            model.password = "first password"
            await model.signIn()
            let account = try #require(model.account)
            try await store.addBasicNotes(count: 1, toDeck: store.addDeck(named: "Local"))
            await model.sync()
            #expect(model.status == .choosingDirection(.uploadOnly))

            model.beginDestinationChange()
            model.serverAddress = second.address
            model.userName = "sam"
            model.password = "wrong password"
            await model.signIn()

            #expect(model.status.failure?.reason == .wrongCredentials)
            #expect(model.account == account)
            #expect(try storage.load() == account)
            #expect(SyncModel(store: store, storage: storage).serverAddress == first.address)
            model.cancelDestinationChange()
            #expect(model.status == .choosingDirection(.uploadOnly))
            #expect(model.serverAddress == first.address)

            model.beginDestinationChange()
            model.serverAddress = second.address
            model.userName = "sam"
            model.password = "second password"
            await model.signIn()

            #expect(model.status == .idle)
            #expect(model.account?.server?.absoluteString == second.address)
            #expect(try storage.load() == model.account)
            #expect(model.account?.hostKey != account.hostKey)
            await model.upload()
            #expect(model.status == .idle, "The previous server's pending transfer ended with its sign-in")
            model.signOut()
            #expect(try storage.load() == nil)
        }
    }

    @Test("An unreachable server is reported with the cause")
    func unreachableServer() async throws {
        let address = try unreachableAddress()
        try await withTemporaryCollection { store in
            let model = SyncModel(store: store, storage: MemoryAccountStorage())
            model.selectDestination(.selfHosted)
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
            model.selectDestination(.selfHosted)
            model.serverAddress = hungServer.address
            model.userName = "alice"
            model.password = "correct horse"

            let clock = ContinuousClock()
            let started = clock.now
            async let signingIn: Void = model.signIn()
            try await eventually("signing in to begin") { model.status == .signingIn }
            model.selectDestination(.ankiWeb)
            model.serverAddress = "https://sync.example.org/"
            #expect(model.destination == .selfHosted)
            #expect(model.serverAddress == hungServer.address)
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
