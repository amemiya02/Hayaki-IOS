import AnkiCore
import AnkiProto

/// The inputs changed only in the simulator until applied to the preset.
public struct FSRSSimulationSettings: Equatable, Sendable {
    public var days = 365
    public var additionalNewCards = 0
    public var desiredRetention: Float
    public var newLimit: Int
    public var reviewLimit: Int
    public var maximumInterval: Int
    public var newCardsIgnoreReviewLimit: Bool
    public var reviewOrder: ReviewSortOrder
    public var easyDays: [Float]
    public var suspendLeeches: Bool
    public var leechThreshold: Int
}

extension DeckOptionsModel {
    var canSimulateFSRS: Bool {
        guard canOptimizeFSRS, let index = selectedIndex else { return false }
        return entries[index].saved?.config.fsrsParams6 == fsrsParameters
    }

    public func fsrsSimulationSettings(workload: Bool) -> FSRSSimulationSettings {
        FSRSSimulationSettings(
            desiredRetention: desiredRetention,
            newLimit: newCardsPerDay,
            reviewLimit: workload ? 9999 : reviewsPerDay,
            maximumInterval: Int(selectedConfig.maximumReviewInterval),
            newCardsIgnoreReviewLimit: settings.newCardsIgnoreReviewLimit,
            reviewOrder: reviewSortOrder,
            easyDays: selectedConfig.easyDaysPercentages,
            suspendLeeches: selectedConfig.leechAction == .suspend,
            leechThreshold: Int(selectedConfig.leechThreshold)
        )
    }

    public func simulateFSRSReviews(_ input: FSRSSimulationSettings) async throws(CoreError) -> Anki_Scheduler_SimulateFsrsReviewResponse {
        try await store.core.simulateFsrsReview(simulationRequest(input))
    }

    public func simulateFSRSWorkload(_ input: FSRSSimulationSettings) async throws(CoreError) -> Anki_Scheduler_SimulateFsrsWorkloadResponse {
        try await store.core.simulateFsrsWorkload(simulationRequest(input))
    }

    func applyFSRSSimulation(_ input: FSRSSimulationSettings, workload: Bool) {
        newCardsPerDay = input.newLimit
        reviewsPerDay = input.reviewLimit
        selectedConfig.maximumReviewInterval = UInt32(clamping: input.maximumInterval)
        if !workload { desiredRetention = input.desiredRetention }
        settings.newCardsIgnoreReviewLimit = input.newCardsIgnoreReviewLimit
        reviewSortOrder = input.reviewOrder
        selectedConfig.easyDaysPercentages = input.easyDays
        selectedConfig.leechAction = input.suspendLeeches ? .suspend : .tagOnly
        selectedConfig.leechThreshold = UInt32(clamping: input.leechThreshold)
    }

    private func simulationRequest(_ input: FSRSSimulationSettings) -> Anki_Scheduler_SimulateFsrsReviewRequest {
        let config = selectedConfig
        return .with {
            $0.params = fsrsParameters
            $0.desiredRetention = Self.validDesiredRetention(input.desiredRetention)
            $0.deckSize = UInt32(min(max(input.additionalNewCards, 0), 100_000))
            $0.daysToSimulate = UInt32(min(max(input.days, 1), 3_650))
            $0.newLimit = UInt32(min(max(input.newLimit, 0), 9999))
            $0.reviewLimit = UInt32(min(max(input.reviewLimit, 0), 9999))
            $0.maxInterval = UInt32(min(max(input.maximumInterval, 1), 36_500))
            $0.search = defaultFSRSParameterSearch
            $0.newCardsIgnoreReviewLimit = input.newCardsIgnoreReviewLimit
            $0.easyDaysPercentages = input.easyDays
            $0.reviewOrder = input.reviewOrder
            if input.suspendLeeches {
                $0.suspendAfterLapseCount = UInt32(min(max(input.leechThreshold, 1), 9999))
            }
            $0.historicalRetention = config.historicalRetention
            $0.learningStepCount = UInt32(clamping: config.learnSteps.count)
            $0.relearningStepCount = UInt32(clamping: config.relearnSteps.count)
        }
    }
}
