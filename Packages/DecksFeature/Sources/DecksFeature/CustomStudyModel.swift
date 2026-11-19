import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Observation
import StudyFeature

@MainActor
@Observable
public final class CustomStudyModel {
    public enum Choice: CaseIterable, Hashable, Sendable {
        case extendNew, extendReviews, reviewForgotten, reviewAhead, previewNew, studyByTag
    }

    public typealias CardSelection = Anki_Scheduler_CustomStudyRequest.Cram.CramKind

    public private(set) var choice: Choice = .extendNew
    public private(set) var availableNew = 0
    public private(set) var availableReviews = 0
    public private(set) var tags: [String] = []
    public private(set) var isLoaded = false
    public private(set) var isWorking = false
    public private(set) var error: String?

    public var amount: UInt32 = 1
    public var cardSelection: CardSelection = .all
    public var includedTags: Set<String> = []
    public var excludedTags: Set<String> = []

    @ObservationIgnored private let store: CollectionStore
    public let deckID: Int64
    @ObservationIgnored private var lastNewAmount: UInt32 = 1
    @ObservationIgnored private var lastReviewAmount: UInt32 = 1

    public init(store: CollectionStore, deckID: Int64) {
        self.store = store
        self.deckID = deckID
    }

    public var canStart: Bool { isLoaded && !isWorking && amount > 0 && amount <= UInt32(Int32.max) }

    public func load() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let defaults = try await store.core.customStudyDefaults(.with { $0.deckID = deckID })
            lastNewAmount = max(1, defaults.extendNew)
            lastReviewAmount = max(1, defaults.extendReview)
            availableNew = Int(defaults.availableNew) + Int(defaults.availableNewInChildren)
            availableReviews = Int(defaults.availableReview) + Int(defaults.availableReviewInChildren)
            tags = defaults.tags.map(\.name)
            includedTags = Set(defaults.tags.filter(\.include).map(\.name))
            excludedTags = Set(defaults.tags.filter(\.exclude).map(\.name))
            choose(choice)
            isLoaded = true
        } catch {
            self.error = error.message
        }
    }

    public func choose(_ choice: Choice) {
        self.choice = choice
        amount = switch choice {
        case .extendNew: lastNewAmount
        case .extendReviews: lastReviewAmount
        case .reviewForgotten, .reviewAhead, .previewNew: 7
        case .studyByTag: 100
        }
    }

    public func start() async -> StudyDeck? {
        guard canStart else { return nil }
        isWorking = true
        error = nil
        defer { isWorking = false }

        let value: Anki_Scheduler_CustomStudyRequest.OneOf_Value = switch choice {
        case .extendNew: .newLimitDelta(Int32(amount))
        case .extendReviews: .reviewLimitDelta(Int32(amount))
        case .reviewForgotten: .forgotDays(amount)
        case .reviewAhead: .reviewAheadDays(amount)
        case .previewNew: .previewDays(amount)
        case .studyByTag: .cram(.with {
            $0.kind = cardSelection
            $0.cardLimit = amount
            $0.tagsToInclude = includedTags.sorted()
            $0.tagsToExclude = excludedTags.subtracting(includedTags).sorted()
        })
        }

        do {
            try await store.modify(.customStudy(.with {
                $0.deckID = deckID
                $0.value = value
            }))
            let target = if choice == .extendNew || choice == .extendReviews {
                try await store.core.getDeck(.with { $0.did = deckID })
            } else {
                try await store.core.getCurrentDeck()
            }
            let name = target.name.components(separatedBy: "::").last ?? target.name
            return StudyDeck(id: target.id, name: name)
        } catch {
            self.error = error.message
            return nil
        }
    }
}
