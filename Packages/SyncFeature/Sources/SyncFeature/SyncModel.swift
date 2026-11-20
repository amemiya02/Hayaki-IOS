import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Network
import Observation

/// Signs in to the selected destination and syncs the collection and its media through Anki's core.
@MainActor
@Observable
public final class SyncModel {
    public enum Destination: Hashable, Sendable {
        case ankiWeb
        case selfHosted
    }

    public enum Badge: Equatable, Sendable {
        case signedOut
        case pendingChanges
        case oneWay
    }

    public enum AutomaticTrigger: Sendable {
        case foreground
        case background
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
    private var draftCertificate = ""
    private var editingCertificate = false

    /// The active destination's certificate, or the draft for a new sign-in.
    public var customCertificate: String {
        if account == nil || isChangingDestination { return draftCertificate }
        return account?.customCertificate ?? ""
    }

    /// The learner's sign-in, or nil when sync is not set up.
    public private(set) var account: SyncAccount?
    public private(set) var status: Status = .idle
    public private(set) var mediaStatus: MediaSyncStatus = .idle

    public var policy: SyncPolicy {
        didSet {
            if let data = try? PropertyListEncoder().encode(policy) {
                preferences?.set(data, forKey: preferenceKeys.policy)
            }
        }
    }

    public var network: SyncNetwork? { networkOverride?() ?? observedNetwork }
    public var needsMeteredConfirmation: Bool { pendingMeteredAction != nil }

    public var badge: Badge? {
        guard policy.showsStatusBadge else { return nil }
        return account == nil ? .signedOut : lastKnownBadge
    }

    private var lastKnownBadge: Badge?
    // The backend caches server status on the collection, so a new sign-in
    // needs a real collection sync before an automatic media-only transfer.
    private var requiresFreshCollectionSync = false
    @ObservationIgnored private var hasLookedUpSyncState = false
    private var checkingStatus = false
    @ObservationIgnored private var didCancelStatusCheck = false
    @ObservationIgnored private var lastAttempt: Date? {
        didSet { preferences?.set(lastAttempt, forKey: preferenceKeys.lastAttempt) }
    }
    @ObservationIgnored private let now: () -> Date

    private enum MeteredAction {
        case collection
        case fullSync(upload: Bool)
        case retryMedia
    }

    private var pendingMeteredAction: MeteredAction?
    private var confirmedMeteredConflict = false
    private var observedNetwork: SyncNetwork? {
        didSet { networkChanged() }
    }
    @ObservationIgnored private var meterPermissionForActiveTransfer: Bool?
    @ObservationIgnored private var requiresUnmeteredMedia = false

    private var statusBeforeDestinationChange: Status?
    private var markingFullSync = false

    public var isChangingDestination: Bool { statusBeforeDestinationChange != nil }

    /// When a collection sync with the current sign-in last finished.
    public var lastCollectionSync: Date? { account?.lastCollectionSync }
    /// When a media sync with the current sign-in last finished.
    public var lastMediaSync: Date? { account?.lastMediaSync }

    @ObservationIgnored private let store: CollectionStore
    @ObservationIgnored private let storage: any SyncAccountStorage
    @ObservationIgnored private let onCollectionDownloaded: (() -> Void)?
    @ObservationIgnored private let preferences: UserDefaults?
    @ObservationIgnored private let preferenceKeys: (policy: String, lastAttempt: String)
    @ObservationIgnored private let networkOverride: (() -> SyncNetwork)?
    @ObservationIgnored private let monitor: NWPathMonitor?
    /// Cancels whatever is running: signing in or a sync.
    @ObservationIgnored private var cancelRunning: (() -> Void)?

    /// - Parameter storage: Where the sign-in is kept; the Keychain unless a
    ///   test passes another.
    /// - Parameter onCollectionDownloaded: Runs after the downloaded collection
    ///   is open and before media sync starts.
    public init(
        store: CollectionStore,
        storage: any SyncAccountStorage = KeychainSyncAccountStorage(),
        preferences: UserDefaults? = nil,
        profileID: UUID? = nil,
        onCollectionDownloaded: (() -> Void)? = nil,
        network: (() -> SyncNetwork)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.storage = storage
        self.onCollectionDownloaded = onCollectionDownloaded
        self.preferences = preferences
        let keys = Self.keys(for: profileID)
        preferenceKeys = keys
        self.now = now
        lastAttempt = preferences?.object(forKey: keys.lastAttempt) as? Date
        policy = preferences?.data(forKey: keys.policy)
            .flatMap { try? PropertyListDecoder().decode(SyncPolicy.self, from: $0) } ?? SyncPolicy()
        networkOverride = network
        monitor = network == nil ? NWPathMonitor() : nil
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
        monitor?.pathUpdateHandler = { [weak self] path in
            let network = SyncNetwork(path)
            Task { @MainActor [weak self] in self?.observedNetwork = network }
        }
        monitor?.start(queue: DispatchQueue(label: "Hayaki Sync Network"))
    }

    deinit {
        monitor?.cancel()
    }

    /// Removes sync preferences when the owning profile is deleted.
    public static func removePolicy(in preferences: UserDefaults, profileID: UUID?) {
        let keys = keys(for: profileID)
        preferences.removeObject(forKey: keys.policy)
        preferences.removeObject(forKey: keys.lastAttempt)
    }

    private static func keys(for profileID: UUID?) -> (policy: String, lastAttempt: String) {
        let policy = profileID.map { "hayakiSyncPolicy.\($0.uuidString)" } ?? "hayakiSyncPolicy"
        return (policy, "\(policy).lastAttempt")
    }

    /// Whether signing in or a collection or media sync is under way.
    public var isBusy: Bool {
        if markingFullSync || checkingStatus || editingCertificate { return true }
        return switch status {
        case .signingIn, .syncing: true
        default:
            if case .syncing = mediaStatus { true } else { false }
        }
    }

    /// Whether the collection or media is being transferred, which Cancel stops.
    public var isTransferring: Bool {
        if case .syncing = status { return true }
        if case .syncing = mediaStatus { return true }
        return false
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
        guard store.allowsNewProfileWork, !isBusy, !isChangingDestination, account != nil,
              policy.media.allows(network), case .synced = status
        else { return false }
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
        draftCertificate = ""
        status = .idle
    }

    /// Edits the destination while keeping the current sign-in available if the change fails.
    public func beginDestinationChange() {
        guard store.allowsNewProfileWork, !isBusy, account != nil, !isChangingDestination else { return }
        statusBeforeDestinationChange = status
        dismissMeteredConfirmation()
        clearSignInForm()
    }

    public func cancelDestinationChange() {
        guard !isBusy, let account, let previousStatus = statusBeforeDestinationChange else { return }
        statusBeforeDestinationChange = nil
        destination = account.server == nil ? .ankiWeb : .selfHosted
        customServerAddress = account.server?.absoluteString ?? ""
        userName = account.userName
        password = ""
        draftCertificate = ""
        status = previousStatus
    }

    /// Validates a PEM using the upstream TLS client. A draft becomes active only
    /// after sign-in succeeds. An edit to an existing sign-in is saved with it.
    public func updateCustomCertificate(_ text: String) async -> SyncFailure? {
        guard store.allowsNewProfileWork, !isBusy, destination == .selfHosted else { return nil }
        let certificate = text.trimmed.nilIfEmpty
        let server = Self.serverURL(from: serverAddress)
        if certificate != nil, server?.scheme?.lowercased() != "https" {
            return SyncFailure(reason: .invalidCertificate)
        }
        editingCertificate = true
        defer { editingCertificate = false }
        if let certificate {
            do {
                try await withCustomCertificate(certificate) {}
            } catch {
                return SyncFailure(reason: .invalidCertificate)
            }
        }
        if account == nil || isChangingDestination {
            draftCertificate = certificate ?? ""
        } else if var account {
            account.customCertificate = certificate
            if let endpoint = account.redirectedEndpoint, !account.acceptsRedirect(to: endpoint) {
                account.redirectedEndpoint = nil
            }
            do {
                try storage.save(account)
                self.account = account
            } catch {
                return SyncFailure(storageError: error)
            }
        }
        return nil
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
        let certificate = server?.scheme?.lowercased() == "https" ? draftCertificate.nilIfEmpty : nil
        let auth: Anki_Sync_SyncAuth
        do {
            auth = try await run(certificate: certificate) {
                store.core.start(.syncLogin(request), abortingWith: .abortSync())
            }
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
        var account = SyncAccount(server: server, userName: request.username, hostKey: auth.hkey)
        account.customCertificate = certificate
        do {
            try storage.save(account)
        } catch {
            status = .failed(SyncFailure(storageError: error))
            return
        }
        self.account = account
        draftCertificate = ""
        requiresFreshCollectionSync = hasLookedUpSyncState
        lastAttempt = nil
        lastKnownBadge = nil
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
        lastAttempt = nil
        lastKnownBadge = nil
        mediaStatus = .idle
        dismissMeteredConfirmation()
        confirmedMeteredConflict = false
        clearSignInForm()
    }

    // MARK: Syncing

    public var canStartManualSync: Bool {
        guard store.allowsNewProfileWork, account != nil, !isBusy, !isChangingDestination else { return false }
        if case .choosingDirection = status { return false }
        return true
    }

    /// Exchanges collection changes, or asks which side to keep if the core
    /// requires a one-way sync.
    public func sync() async {
        await request(.collection)
    }

    /// Checks the upstream status before transferring. Unchanged collections
    /// can transfer media independently. A background trigger skips the foreground cooldown.
    @discardableResult
    public func automaticSync(_ trigger: AutomaticTrigger) async -> Bool {
        guard policy.automatic, networkAllowsAutomaticTransfer, let account,
              canCheckStatus, pendingMeteredAction == nil
        else { return false }
        if trigger == .foreground, let lastAttempt, now().timeIntervalSince(lastAttempt) <= 600 { return false }

        meterPermissionForActiveTransfer = policy.allowsMetered
        defer {
            lastAttempt = now()
            meterPermissionForActiveTransfer = nil
        }

        if requiresFreshCollectionSync {
            await syncCollection(meteredConsent: false, automatically: true)
            return true
        }

        let previousStatus = status
        status = .syncing(.connecting)
        do {
            let required = try await checkStatus(for: account)
            guard !didCancelStatusCheck, networkAllowsAutomaticTransfer else {
                status = previousStatus
                return true
            }
            if required == .normalSync || required == .fullSync {
                await syncCollection(meteredConsent: false, automatically: true)
            } else {
                // A manually cancelled media transfer stays paused until a manual sync or retry.
                guard mediaStatus != .cancelled, policy.media.allows(network) else {
                    status = previousStatus
                    return true
                }
                let outcome = SyncOutcome(kind: .merged, serverMessage: nil)
                status = .synced(outcome)
                await syncMedia(after: outcome)
            }
        } catch {
            status = .failed(SyncFailure(error, server: account.server, signingIn: false))
        }
        return true
    }

    /// Reads pending collection work for the Decks sync control.
    public func refreshBadge() async {
        guard policy.showsStatusBadge, networkAllowsAutomaticTransfer, !requiresFreshCollectionSync,
              let account, canCheckStatus
        else { return }
        do {
            _ = try await checkStatus(for: account)
        } catch {
            lastKnownBadge = nil
        }
    }

    private var canCheckStatus: Bool {
        guard store.allowsNewProfileWork, !isBusy, !isChangingDestination else { return false }
        if case .choosingDirection = status { return false }
        return true
    }

    private var networkAllowsAutomaticTransfer: Bool {
        network == .unmetered || (network == .metered && policy.allowsMetered)
    }

    private func checkStatus(for account: SyncAccount) async throws(CoreError) -> Anki_Sync_SyncStatusResponse.Required {
        hasLookedUpSyncState = true
        checkingStatus = true
        didCancelStatusCheck = false
        cancelRunning = { [weak self] in self?.didCancelStatusCheck = true }
        defer {
            cancelRunning = nil
            checkingStatus = false
        }
        SyncClientIdentity.install()
        let result = try await withCustomCertificate(account.certificateForRequests) { () async throws(CoreError) in
            try await store.core.lookupSyncStatus(account.auth(timeoutSeconds: policy.timeoutSeconds))
        }
        if result.hasNewEndpoint, let failure = follow(newEndpoint: result.newEndpoint, for: account) {
            throw CoreError(kind: .invalidInput, message: failure.message)
        }
        lastKnownBadge = switch result.required {
        case .noChanges, .UNRECOGNIZED: nil
        case .normalSync: .pendingChanges
        case .fullSync: .oneWay
        }
        return result.required
    }

    public func dismissMeteredConfirmation() {
        pendingMeteredAction = nil
    }

    public func confirmMeteredSync(alwaysAllow: Bool) async {
        guard let action = pendingMeteredAction else { return }
        pendingMeteredAction = nil
        guard store.allowsNewProfileWork, !isBusy, !isChangingDestination, account != nil else { return }
        if alwaysAllow { policy.allowsMetered = true }
        await perform(action, meteredConsent: true)
    }

    private func request(_ action: MeteredAction, meteredConsent: Bool = false) async {
        guard store.allowsNewProfileWork, !isBusy, !isChangingDestination,
              account != nil, pendingMeteredAction == nil else { return }
        if case .retryMedia = action, !canRetryMediaSync { return }
        if network == .metered && !policy.allowsMetered && !meteredConsent {
            pendingMeteredAction = action
        } else {
            await perform(action, meteredConsent: meteredConsent)
        }
    }

    private func perform(_ action: MeteredAction, meteredConsent: Bool) async {
        meterPermissionForActiveTransfer = policy.allowsMetered || meteredConsent
        defer {
            lastAttempt = now()
            meterPermissionForActiveTransfer = nil
        }
        switch action {
        case .collection:
            await syncCollection(meteredConsent: meteredConsent)
        case .fullSync(let upload):
            await fullSync(upload: upload)
        case .retryMedia:
            guard canRetryMediaSync, case .synced(let outcome) = status else { return }
            SyncClientIdentity.install()
            await syncMedia(after: outcome)
        }
    }

    private func networkChanged() {
        guard let meterPermissionForActiveTransfer else { return }
        if network == .metered && (!meterPermissionForActiveTransfer || requiresUnmeteredMedia) {
            cancel()
        }
    }

    private func syncCollection(meteredConsent: Bool, automatically: Bool = false) async {
        guard let account else { return }
        hasLookedUpSyncState = true
        confirmedMeteredConflict = meteredConsent
        SyncClientIdentity.install()
        status = .syncing(.connecting)
        let request = Anki_Sync_SyncCollectionRequest.with {
            $0.auth = account.auth(timeoutSeconds: policy.timeoutSeconds)
            // Start media separately once the collection result is known.
            $0.syncMedia = false
        }
        let response: Anki_Sync_SyncCollectionResponse
        do {
            response = try await run(certificate: account.certificateForRequests) {
                store.core.start(.syncCollection(request), abortingWith: .abortSync())
            }
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
            lastKnownBadge = .oneWay
            status = .choosingDirection(.either)
        case .fullDownload:
            lastKnownBadge = .oneWay
            status = .choosingDirection(.downloadOnly)
        case .fullUpload:
            lastKnownBadge = .oneWay
            status = .choosingDirection(.uploadOnly)
        case .noChanges, .normalSync, .UNRECOGNIZED:
            // A finished normal sync reports no further changes required.
            await finishCollectionSync(
                SyncOutcome(kind: .merged, serverMessage: response.serverMessage.nilIfEmpty),
                syncMedia: !automatically || mediaStatus != .cancelled
            )
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
            lastKnownBadge = .oneWay
            status = .fullSyncRequested
            return true
        } catch {
            status = .failed(SyncFailure(error, server: account.server, signingIn: false))
            return false
        }
    }

    /// Replaces the server's collection with this device's.
    public func upload() async {
        guard case .choosingDirection(let choice) = status, choice.allowsUpload else { return }
        await request(.fullSync(upload: true), meteredConsent: confirmedMeteredConflict)
    }

    /// Replaces this device's collection with the server's.
    public func download() async {
        guard case .choosingDirection(let choice) = status, choice.allowsDownload else { return }
        await request(.fullSync(upload: false), meteredConsent: confirmedMeteredConflict)
    }

    /// Leaves both sides as they are, when asked to choose a direction.
    public func keepBoth() {
        guard case .choosingDirection = status else { return }
        confirmedMeteredConflict = false
        dismissMeteredConfirmation()
        status = .idle
    }

    /// Stops signing in or the transfer under way. The core keeps completed
    /// media batches so the next sync can continue.
    public func cancel() {
        cancelRunning?()
    }

    /// Continues a previous media transfer with the same sign-in.
    public func retryMediaSync() async {
        await request(.retryMedia)
    }

    private func fullSync(upload: Bool) async {
        guard store.allowsNewProfileWork, !isChangingDestination, let account, case .choosingDirection(let choice) = status,
              upload ? choice.allowsUpload : choice.allowsDownload
        else { return }
        status = .syncing(upload ? .uploading(transferred: 0, total: 0) : .downloading(transferred: 0, total: 0))
        let request = Anki_Sync_FullUploadOrDownloadRequest.with {
            $0.auth = account.auth(timeoutSeconds: policy.timeoutSeconds)
            $0.upload = upload
            // Leaving serverUsn unset lets us start media as a separate phase.
        }
        do {
            _ = try await run(certificate: account.certificateForRequests) {
                store.core.start(.fullUploadOrDownload(request), abortingWith: .abortSync())
            }
        } catch {
            status = .failed(SyncFailure(error, server: account.server, signingIn: false))
            return
        }
        // The core closed the collection and opened it again, replaced when
        // downloading.
        await finishCollectionSync(SyncOutcome(kind: upload ? .uploaded : .downloaded, serverMessage: nil))
    }

    private func finishCollectionSync(_ outcome: SyncOutcome, syncMedia: Bool = true) async {
        store.signal(.everything)
        requiresFreshCollectionSync = false
        lastKnownBadge = nil
        if var account {
            account.lastCollectionSync = now()
            // The time is only shown, so a Keychain failure must not turn a
            // finished sync into a failed one; it is kept for this launch.
            try? storage.save(account)
            self.account = account
        }
        status = .synced(outcome)
        if outcome.kind == .downloaded { onCollectionDownloaded?() }
        if syncMedia { await self.syncMedia(after: outcome) }
    }

    private func syncMedia(after outcome: SyncOutcome) async {
        guard var account, policy.media.allows(network),
              network != .metered || meterPermissionForActiveTransfer == true
        else { return }
        requiresUnmeteredMedia = policy.media == .onlyUnmetered
        defer { requiresUnmeteredMedia = false }
        mediaStatus = .syncing(nil)
        func save(_ phase: SavedMediaSync.Phase) throws {
            account.mediaSync = SavedMediaSync(phase: phase, collection: outcome)
            if phase == .synced { account.lastMediaSync = now() }
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
            _ = try await run(certificate: account.certificateForRequests) {
                store.core.startMediaSync(account.auth(timeoutSeconds: policy.timeoutSeconds))
            }
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

    /// The upstream certificate API replaces the backend HTTP client. Restore
    /// normal trust after the operation, including a background media transfer.
    private func withCustomCertificate<Response>(
        _ certificate: String?,
        operation: () async throws(CoreError) -> Response
    ) async throws(CoreError) -> Response {
        guard let certificate else { return try await operation() }
        let accepted = try await store.core.setCustomCertificate(.with { $0.val = certificate })
        guard accepted.val else {
            throw CoreError(
                kind: .invalidInput,
                message: String(localized: "Enter one valid PEM certificate for an HTTPS sync server.", bundle: .module)
            )
        }
        let result: Result<Response, CoreError>
        do {
            result = .success(try await operation())
        } catch {
            result = .failure(error)
        }
        _ = try await store.core.setCustomCertificate(.init())
        return try result.get()
    }

    /// Runs a long operation, showing its progress and making it cancellable.
    private func run<Response>(
        certificate: String?,
        start: () -> LongOperation<Response>
    ) async throws(CoreError) -> Response {
        try await withCustomCertificate(certificate) { () async throws(CoreError) in
            let operation = start()
            cancelRunning = { operation.cancel() }
            // The network may have changed while the certificate was installed.
            networkChanged()
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

    var certificateForRequests: String? {
        guard server?.scheme?.lowercased() == "https" else { return nil }
        return customCertificate?.trimmed.nilIfEmpty
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
        if certificateForRequests != nil, let server {
            return scheme == "https" && host.lowercased() == server.host()?.lowercased()
                && (url.port ?? 443) == (server.port ?? 443)
        }
        return !url.isAnkiWebHost
    }

    func auth(timeoutSeconds: Int) -> Anki_Sync_SyncAuth {
        .with {
            $0.hkey = hostKey
            $0.ioTimeoutSecs = UInt32(timeoutSeconds)
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
