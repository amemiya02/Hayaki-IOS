import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Observation

public struct FilteredDeckFilter: Equatable, Sendable {
    public typealias Order = Anki_Decks_Deck.Filtered.SearchTerm.Order

    public var search: String
    public var limit: UInt32
    public var order: Order

    public init(search: String = "", limit: UInt32 = 100, order: Order = .due) {
        self.search = search
        self.limit = limit
        self.order = order
    }

    init(_ term: Anki_Decks_Deck.Filtered.SearchTerm) {
        self.init(search: term.search, limit: term.limit, order: term.order)
    }

    var proto: Anki_Decks_Deck.Filtered.SearchTerm {
        .with {
            $0.search = search
            $0.limit = limit
            $0.order = order
        }
    }
}

/// Edits and rebuilds a filtered deck through the scheduler.
@MainActor
@Observable
public final class FilteredDeckModel {
    public private(set) var deckID: Int64?
    public private(set) var isWorking = false
    public private(set) var error: String?

    public var name = ""
    public var reschedule = true
    public var primary = FilteredDeckFilter()
    public var secondary: FilteredDeckFilter?
    public var previewAgainSeconds: UInt32 = 0
    public var previewHardSeconds: UInt32 = 0
    public var previewGoodSeconds: UInt32 = 0

    @ObservationIgnored private let store: CollectionStore
    private var request: Anki_Decks_FilteredDeckForUpdate?

    public init(store: CollectionStore, deckID: Int64? = nil) {
        self.store = store
        self.deckID = deckID
    }

    public var isLoaded: Bool { request != nil }
    public var canBuild: Bool {
        isLoaded && !isWorking && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func load() async {
        let did = deckID ?? 0
        await run {
            let saved = try await store.core.getOrCreateFilteredDeck(.with { $0.did = did })
            request = saved
            name = saved.name
            reschedule = saved.config.reschedule
            primary = saved.config.searchTerms.first.map(FilteredDeckFilter.init) ?? FilteredDeckFilter()
            secondary = saved.config.searchTerms.dropFirst().first.map(FilteredDeckFilter.init)
            previewAgainSeconds = saved.config.previewAgainSecs
            previewHardSeconds = saved.config.previewHardSecs
            previewGoodSeconds = saved.config.previewGoodSecs
        }
    }

    /// Saves and fills the deck in a single core operation.
    @discardableResult
    public func build() async -> Int64? {
        guard canBuild, var updated = request else { return nil }
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.config.searchTerms = [primary.proto] + (secondary.map { [$0.proto] } ?? [])
        updated.config.reschedule = reschedule
        updated.config.previewAgainSecs = previewAgainSeconds
        updated.config.previewHardSecs = previewHardSeconds
        updated.config.previewGoodSecs = previewGoodSeconds
        let changes = updated
        return await run {
            let saved = try await store.modify(.addOrUpdateFilteredDeck(changes))
            updated.id = saved.id
            request = updated
            deckID = saved.id
            return saved.id
        }
    }

    public func rebuild() async {
        guard let deckID else { return }
        await run {
            try await store.modify(.rebuildFilteredDeck(.with { $0.did = deckID }))
        }
    }

    public func empty() async {
        guard let deckID else { return }
        await run {
            try await store.modify(.emptyFilteredDeck(.with { $0.did = deckID }))
        }
    }

    @discardableResult
    private func run<Result>(_ action: () async throws -> Result) async -> Result? {
        guard !isWorking else { return nil }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            return try await action()
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}
