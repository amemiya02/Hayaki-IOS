import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Observation

/// Signs in to the selected destination and syncs the collection and its media through Anki's core.
@MainActor
@Observable
public final class SyncModel {
    public enum Destination: Hashable, Sendable {
        case ankiWeb
        case selfHosted
    }

    public enum Status: Equatable, Sendable {
        case idle
        case signingIn
        case syncing(SyncProgress)
        /// The two sides cannot be merged; one must replace the other. Waits
        /// for `upload()`, `download()` or `keepBoth()`.
        case choosingDirection(FullSyncChoice)
        case fullSyncRequested
        case synced(SyncOutcome)
        case failed(SyncFailure)

        public var failure: SyncFailure? {
            if case .failed(let failure) = self { failure } else { nil }
        }
    }

    public private(set) var destination: Destination = .ankiWeb

    private var customServerAddress = ""
    public var serverAddress: String {
        get { customServerAddress }
        set {
            guard canEditSignIn, destination == .selfHosted else { return }
            if newValue.trimmed != customServerAddress.trimmed {
                clearSignInForm()
            }
            customServerAddress = newValue
        }
    }

    public var userName = ""
    public var password = ""

    /// The learner's sign-in, or nil when sync is not set up.
    public private(set) var account: SyncAccount?
    public private(set) var status: Status = .idle
    public private(set) var mediaStatus: MediaSyncStatus = .idle

    private var statusBeforeDestinationChange: Status?
    private var markingFullSync = false

    public var isChangingDestination: Bool { statusBeforeDestinationChange != nil }

    @ObservationIgnored private let store: CollectionStore
    @ObservationIgnored private let storage: any SyncAccountStorage
    /// Cancels whatever is running: signing in or a sync.
    @ObservationIgnored private var cancelRunning: (() -> Void)?

    /// - Parameter storage: Where the sign-in is kept; the Keychain unless a
    ///   test passes another.
    public init(store: CollectionStore, storage: any SyncAccountStorage = KeychainSyncAccountStorage()) {
        self.store = store
        self.storage = storage
        do {
            account = try storage.load()
        } catch {
            status = .failed(SyncFailure(storageError: error))
        }
        if let account {
            if let server = account.server {
                destination = .selfHosted
                customServerAddress = server.absoluteString
            }
            userName = account.userName
            if let saved = account.mediaSync {
                status = .synced(saved.collection)
                mediaStatus = saved.status
            }
        }
    }

    /// Whether signing in or a collection or media sync is under way.
    public var isBusy: Bool {
        if markingFullSync { return true }
        return switch status {
        case .signingIn, .syncing: true
        default:
            if case .syncing = mediaStatus { true } else { false }
        }
    }

    private var canEditSignIn: Bool {
        store.allowsNewProfileWork && !isBusy && (account == nil || isChangingDestination)
    }

    public var canSignIn: Bool {
        canEditSignIn
            && (destination == .ankiWeb || !serverAddress.trimmed.isEmpty)
            && !userName.trimmed.isEmpty && !password.isEmpty
    }

    public var canRetryMediaSync: Bool {
        guard store.allowsNewProfileWork, !isBusy, !isChangingDestination, account != nil, case .synced = status else { return false }
        return switch mediaStatus {
        case .cancelled, .interrupted, .failed: true
        default: false
        }
    }

    public func selectDestination(_ destination: Destination) {
        guard canEditSignIn, destination != self.destination else { return }
        self.destination = destination
        clearSignInForm()
    }

    private func clearSignInForm() {
        userName = ""
        password = ""
        status = .idle
    }

    /// Edits the destination while keeping the current sign-in available if the change fails.
    public func beginDestinationChange() {
        guard store.allowsNewProfileWork, !isBusy, account != nil, !isChangingDestination else { return }
        statusBeforeDestinationChange = status
        clearSignInForm()
    }

    public func cancelDestinationChange() {
        guard !isBusy, let account, let previousStatus = statusBeforeDestinationChange else { return }
        statusBeforeDestinationChange = nil
        destination = account.server == nil ? .ankiWeb : .selfHosted
        customServerAddress = account.server?.absoluteString ?? ""
        userName = account.userName
        password = ""
        status = previousStatus
    }

    // MARK: Signing in and out

    /// Exchanges the user name and password for the server's key, and keeps
    /// the key. The password is only ever held in this form while signing in,
    /// and is cleared once the server has issued its key.
    public func signIn() async {
        guard canSignIn else { return }
        let server = destination == .selfHosted ? Self.serverURL(from: serverAddress) : nil
        if destination == .selfHosted, server?.isAnkiWebHost != false {
            status = .failed(SyncFailure(reason: .invalidAddress))
            return
        }
        SyncClientIdentity.install()
        status = .signingIn
        let request = Anki_Sync_SyncLoginRequest.with {
            $0.username = userName.trimmed
            $0.password = password
            if let server {
                $0.endpoint = server.absoluteString
            }
        }
        let auth: Anki_Sync_SyncAuth
        do {
            auth = try await run(store.core.start(.syncLogin(request), abortingWith: .abortSync()))
        } catch {
            status = .failed(SyncFailure(error, server: server, signingIn: true))
            return
        }
        password = ""
        do {
            // The saved media sequence belongs to the previous sign-in. The
            // core can rediscover the existing files against this account.
            try await store.core.resetMediaDatabase(at: store.location.mediaDatabase)
        } catch {
            status = .failed(SyncFailure(error, server: server, signingIn: true))
            return
        }
        let account = SyncAccount(server: server, userName: request.username, hostKey: auth.hkey)
        do {
            try storage.save(account)
        } catch {
            status = .failed(SyncFailure(storageError: error))
            return
        }
        self.account = account
        mediaStatus = .idle
        statusBeforeDestinationChange = nil
        userName = account.userName
        status = .idle
    }

    /// Forgets the sign-in and removes the server's key from this device.
    public func signOut() {
        guard store.allowsNewProfileWork, !isBusy, !isChangingDestination else { return }
        do {
            try storage.remove()
        } catch {
            status = .failed(SyncFailure(storageError: error))
            return
        }
        account = nil
        mediaStatus = .idle
        clearSignInForm()
    }

    // MARK: Syncing

    /// Syncs the collection with the server: sends this device's changes and
    /// fetches the server's. When the two cannot be merged, stops at
    /// `.choosingDirection` without changing either side.
    public func sync() async {
        guard store.allowsNewProfileWork, let account, !isBusy, !isChangingDestination else { return }
        SyncClientIdentity.install()
        status = .syncing(.connecting)
        let request = Anki_Sync_SyncCollectionRequest.with {
            $0.auth = account.auth
            // Start media separately once the collection result is known.
            $0.syncMedia = false
        }
        let response: Anki_Sync_SyncCollectionResponse
        do {
            response = try await run(store.core.start(.syncCollection(request), abortingWith: .abortSync()))
        } catch {
            status = .failed(SyncFailure(error, server: account.server, signingIn: false))
            return
        }
        if response.hasNewEndpoint, let failure = follow(newEndpoint: response.newEndpoint, for: account) {
            store.signal(.everything)
            status = .failed(failure)
            return
        }
        switch response.required {
        case .fullSync:
            status = .choosingDirection(.either)
        case .fullDownload:
            status = .choosingDirection(.downloadOnly)
        case .fullUpload:
            status = .choosingDirection(.uploadOnly)
        case .noChanges, .normalSync, .UNRECOGNIZED:
            // A finished normal sync reports no further changes required.
            await finishCollectionSync(SyncOutcome(kind: .merged, serverMessage: response.serverMessage.nilIfEmpty))
        }
    }

    public var canForceFullSync: Bool {
        guard store.allowsNewProfileWork, account != nil, !isBusy, !isChangingDestination else { return false }
        if case .choosingDirection = status { return false }
        return status != .fullSyncRequested
    }

    /// Asks the core to require an upload or download at the next sync.
    @discardableResult
    public func forceFullSync() async -> Bool {
        guard canForceFullSync, let account else { return false }
        markingFullSync = true
        defer { markingFullSync = false }

        // The pinned core exposes the database command Android uses for
        // Collection.setSchemaModified(). Keep its schema and modified times
        // newer than the prior sync even if the device's clock changed.
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        let command = Data("""
            {"kind":"query","sql":"UPDATE col SET scm=max(?, scm+1, ls+1), mod=max(?, mod+1)","args":[\(now),\(now)],"first_row_only":false}
            """.utf8)
        do {
            _ = try await store.core.runDbCommand(.with { $0.json = command })
            store.signal(.everything)
            status = .fullSyncRequested
            return true
        } catch {
            status = .failed(SyncFailure(error, server: account.server, signingIn: false))
            return false
        }
    }

    /// Replaces the server's collection with this device's.
    public func upload() async {
        await fullSync(upload: true)
    }

    /// Replaces this device's collection with the server's.
    public func download() async {
        await fullSync(upload: false)
    }

    /// Leaves both sides as they are, when asked to choose a direction.
    public func keepBoth() {
        guard case .choosingDirection = status else { return }
        status = .idle
    }

    /// Stops signing in or the transfer under way. The core keeps completed
    /// media batches so the next sync can continue.
    public func cancel() {
        cancelRunning?()
    }

    /// Continues a previous media transfer with the same sign-in.
    public func retryMediaSync() async {
        guard canRetryMediaSync, case .synced(let outcome) = status else { return }
        SyncClientIdentity.install()
        await syncMedia(after: outcome)
    }

    private func fullSync(upload: Bool) async {
        guard store.allowsNewProfileWork, !isChangingDestination, let account, case .choosingDirection(let choice) = status,
              upload ? choice.allowsUpload : choice.allowsDownload
        else { return }
        status = .syncing(upload ? .uploading(transferred: 0, total: 0) : .downloading(transferred: 0, total: 0))
        let request = Anki_Sync_FullUploadOrDownloadRequest.with {
            $0.auth = account.auth
            $0.upload = upload
            // Leaving serverUsn unset lets us start media as a separate phase.
        }
        do {
            _ = try await run(store.core.start(.fullUploadOrDownload(request), abortingWith: .abortSync()))
        } catch {
            status = .failed(SyncFailure(error, server: account.server, signingIn: false))
            return
        }
        // The core closed the collection and opened it again, replaced when
        // downloading.
        await finishCollectionSync(SyncOutcome(kind: upload ? .uploaded : .downloaded, serverMessage: nil))
    }

    private func finishCollectionSync(_ outcome: SyncOutcome) async {
        store.signal(.everything)
        status = .synced(outcome)
        await syncMedia(after: outcome)
    }

    private func syncMedia(after outcome: SyncOutcome) async {
        guard var account else { return }
        mediaStatus = .syncing(nil)
        func save(_ phase: SavedMediaSync.Phase) throws {
            account.mediaSync = SavedMediaSync(phase: phase, collection: outcome)
            try storage.save(account)
            self.account = account
        }

        do {
            try save(.transferring)
        } catch {
            mediaStatus = .failed(SyncFailure(storageError: error))
            return
        }
        let phase: SavedMediaSync.Phase
        let result: MediaSyncStatus
        do {
            _ = try await run(store.core.startMediaSync(account.auth))
            phase = .synced
            result = .synced
        } catch {
            if error.isInterrupted {
                phase = .cancelled
                result = .cancelled
            } else {
                phase = .failed
                result = .failed(SyncFailure(error, server: account.server, signingIn: false))
            }
        }

        do {
            try save(phase)
            mediaStatus = result
        } catch {
            mediaStatus = .failed(SyncFailure(storageError: error))
        }
    }

    /// Runs a long operation, showing its progress and making it cancellable.
    private func run<Response>(_ operation: LongOperation<Response>) async throws(CoreError) -> Response {
        cancelRunning = { operation.cancel() }
        let progress = Task {
            for await report in operation.progress {
                show(report)
            }
        }
        defer {
            cancelRunning = nil
            progress.cancel()
        }
        return try await operation.result
    }

    private func show(_ report: Anki_Collection_Progress) {
        if case .syncing = mediaStatus, case .mediaSync(let media) = report.value {
            mediaStatus = .syncing(MediaSyncProgress(checked: media.checked, added: media.added, removed: media.removed))
            return
        }
        guard case .syncing(let current) = status else { return }
        switch report.value {
        case .normalSync(let sync):
            status = .syncing(.syncing(detail: sync.added.nilIfEmpty))
        case .fullSync(let transfer):
            let transferred = Int(transfer.transferred), total = Int(transfer.total)
            switch current {
            case .uploading: status = .syncing(.uploading(transferred: transferred, total: total))
            case .downloading: status = .syncing(.downloading(transferred: transferred, total: total))
            default: break
            }
        default:
            break
        }
    }

    /// Remember the core's redirect for this sign-in, including across launches.
    private func follow(newEndpoint: String, for account: SyncAccount) -> SyncFailure? {
        guard let url = Self.serverURL(from: newEndpoint), account.acceptsRedirect(to: url) else {
            return SyncFailure(reason: .unexpectedRedirect)
        }
        guard url != account.endpoint else { return nil }

        var redirected = account
        redirected.redirectedEndpoint = url == account.server ? nil : url
        do {
            try storage.save(redirected)
        } catch {
            return SyncFailure(storageError: error)
        }
        self.account = redirected
        return nil
    }

    /// The address as the core expects it: a web address with a host, whose
    /// path ends in a slash (the core resolves its endpoints relative to it).
    static func serverURL(from text: String) -> URL? {
        guard var components = URLComponents(string: text.trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil
        else { return nil }
        if !components.path.hasSuffix("/") {
            components.path += "/"
        }
        return components.url
    }
}

/// Where a sync stands while it runs.
public enum SyncProgress: Equatable, Sendable {
    case connecting
    /// Exchanging changes; `detail` is the core's count of what was sent and
    /// received so far, such as "Added/modified: 3↑ 0↓".
    case syncing(detail: String?)
    case uploading(transferred: Int, total: Int)
    case downloading(transferred: Int, total: Int)
}

/// Which way a full sync may go, when the two sides cannot be merged.
public enum FullSyncChoice: Equatable, Sendable {
    /// Both sides have cards; the learner picks which one to keep.
    case either
    /// The server has no cards, so there is nothing to download.
    case uploadOnly
    /// This device has no cards, so there is nothing to upload.
    case downloadOnly

    public var allowsUpload: Bool { self != .downloadOnly }
    public var allowsDownload: Bool { self != .uploadOnly }
}

public struct SyncOutcome: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Changes were exchanged both ways (or there were none).
        case merged
        case uploaded
        case downloaded
    }

    public let kind: Kind
    /// A message the server sent along, if any.
    public let serverMessage: String?

    public init(kind: Kind, serverMessage: String?) {
        self.kind = kind
        self.serverMessage = serverMessage
    }
}

extension SyncAccount {
    var endpoint: URL? {
        guard let redirectedEndpoint, acceptsRedirect(to: redirectedEndpoint) else { return server }
        return redirectedEndpoint
    }

    func acceptsRedirect(to url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty,
              url.user() == nil, url.password() == nil
        else { return false }

        if server == nil {
            return scheme == "https" && (url.port ?? 443) == 443 && url.isAnkiWebHost
        }
        return !url.isAnkiWebHost
    }

    var auth: Anki_Sync_SyncAuth {
        .with {
            $0.hkey = hostKey
            if let endpoint {
                $0.endpoint = endpoint.absoluteString
            }
        }
    }
}

private extension URL {
    var isAnkiWebHost: Bool {
        guard let host = host()?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) else {
            return false
        }
        return host == "ankiweb.net" || host.hasSuffix(".ankiweb.net")
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
