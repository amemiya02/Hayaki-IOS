import AnkiCore
import AnkiProto
import Foundation
import Synchronization

/// The learner's open collection.
///
/// The store is the only place that knows where the collection lives, and it
/// owns opening, closing and replacing it. Feature models read through `core`
/// and make every change that modifies the collection through `modify(_:)`,
/// which signals the change to every subscriber of `changes()`.
public final class CollectionStore: Sendable {
    /// The Core Client the collection is open in. Use it directly for calls
    /// that only read.
    public let core: CoreClient
    public let location: CollectionLocation
    private let subscribers = Mutex<[UUID: AsyncStream<CollectionChange>.Continuation]>([:])

    private init(core: CoreClient, location: CollectionLocation) {
        self.core = core
        self.location = location
    }

    /// Opens the collection at `location`, creating an empty one if there is
    /// none yet. The work happens on the Core Client's worker thread.
    public static func open(at location: CollectionLocation, core: CoreClient) async throws(CoreError) -> CollectionStore {
        do {
            // The core creates the collection file but not the media folder,
            // which exporting with media needs.
            try FileManager.default.createDirectory(at: location.mediaFolder, withIntermediateDirectories: true)
        } catch {
            throw CoreError(kind: .ioError, message: error.localizedDescription)
        }
        try await core.openCollection(location.openRequest)
        return CollectionStore(core: core, location: location)
    }

    /// Closes the collection. Nothing may use the store afterwards.
    public func close() async throws(CoreError) {
        try await core.closeCollection(.init())
    }

    /// Replaces the collection: closes it, runs `body` (which may overwrite
    /// the files at `location`, for example by importing a collection package
    /// through the core), opens the collection again and signals that
    /// everything changed. The collection is reopened even if `body` throws.
    public func replace(
        isolation: isolated (any Actor)? = #isolation,
        _ body: (_ core: CoreClient, _ location: CollectionLocation) async throws -> Void
    ) async throws {
        try await close()
        var failure: (any Error)?
        do {
            try await body(core, location)
        } catch {
            failure = error
        }
        try await core.openCollection(location.openRequest)
        signal(.everything)
        if let failure { throw failure }
    }

    /// Runs a call that modifies the collection and signals what it changed.
    @discardableResult
    public func modify<Response: CollectionChanging>(_ call: CoreCall<Response>) async throws(CoreError) -> Response {
        let response = try await core.perform(call)
        signal(CollectionChange(response.collectionChanges))
        return response
    }

    /// The name of the operation `undo()` would revert, in the core's
    /// language, such as "Add Deck"; nil when there is nothing to undo.
    public func undoableAction() async throws(CoreError) -> String? {
        let name = try await core.getUndoStatus().undo
        return name.isEmpty ? nil : name
    }

    /// Reverts the last operation that can be undone, signals what that
    /// changed, and returns the operation's name.
    @discardableResult
    public func undo() async throws(CoreError) -> String {
        try await modify(.undo()).operation
    }

    /// The changes made to the collection from now on, one element per
    /// modifying operation, in order. Each call returns a new subscription;
    /// it ends when the task iterating it is cancelled or the stream is
    /// dropped.
    public func changes() -> AsyncStream<CollectionChange> {
        let (stream, continuation) = AsyncStream<CollectionChange>.makeStream()
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.subscribers.withLock { _ = $0.removeValue(forKey: id) }
        }
        subscribers.withLock { $0[id] = continuation }
        return stream
    }

    /// Tells every subscriber that the collection changed. `modify(_:)` and
    /// `replace(_:)` signal by themselves; call this only after a change the
    /// core makes without a change summary, such as a sync.
    public func signal(_ change: CollectionChange) {
        guard !change.isEmpty else { return }
        for continuation in subscribers.withLock({ Array($0.values) }) {
            continuation.yield(change)
        }
    }
}
