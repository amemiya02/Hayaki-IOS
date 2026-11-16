import AnkiCore
import CollectionStore
import Foundation
import Observation

/// The app at launch: starts the core and opens the learner's collection, in
/// the background, creating an empty collection the first time.
@MainActor
@Observable
public final class AppModel {
    public enum State {
        case opening
        case ready(CollectionStore)
        case failed(message: String)
    }

    public private(set) var state: State = .opening

    @ObservationIgnored private let location: @Sendable () throws -> CollectionLocation
    @ObservationIgnored private let language: String

    /// - Parameters:
    ///   - location: Where the collection lives; the app's standard place
    ///     unless a test passes another.
    ///   - language: The language for the core's own text, which must be the
    ///     one the app's screens resolved to.
    public init(
        location: @escaping @Sendable () throws -> CollectionLocation = { try .standard() },
        language: String = AppModel.screenLanguage
    ) {
        self.location = location
        self.language = language
    }

    /// The open collection, once it is ready.
    public var store: CollectionStore? {
        if case .ready(let store) = state { store } else { nil }
    }

    /// Opens the collection unless it is already open or opening has failed.
    /// The core does the work on its own thread, so the interface stays
    /// responsive meanwhile.
    public func open() async {
        guard case .opening = state else { return }
        do {
            let core = try await CoreClient(language: language)
            let store = try await CollectionStore.open(at: try location(), core: core)
            state = .ready(store)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    /// The language the app's own screens are shown in: the first of the
    /// learner's preferred languages that the app has strings for.
    public nonisolated static var screenLanguage: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }
}
