import AnkiCore
import AnkiProto
import CollectionStore
import Foundation

/// Setup actions for a known review history, such as statistics tests need.
/// Like the other setup actions, each goes through the real core.
extension CollectionStore {
    /// Answers one particular card with `rating`, as the study screen does,
    /// but recorded as if it happened `daysAgo` days ago and took `seconds`.
    /// The card is answered from whatever state it is in now.
    public func review(
        _ cardID: Int64,
        rating: Anki_Scheduler_CardAnswer.Rating,
        daysAgo: Int = 0,
        seconds: Int = 3
    ) async throws {
        let states = try await core.getSchedulingStates(.with { $0.cid = cardID })
        let newState: Anki_Scheduler_SchedulingState = switch rating {
        case .again: states.again
        case .hard: states.hard
        case .good: states.good
        case .easy: states.easy
        case .UNRECOGNIZED: states.current
        }
        // The core records the review at the time it was answered.
        let answeredAt = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        try await modify(.answerCard(.with {
            $0.cardID = cardID
            $0.currentState = states.current
            $0.newState = newState
            $0.rating = rating
            $0.answeredAtMillis = Int64(answeredAt.timeIntervalSince1970 * 1000)
            $0.millisecondsTaken = UInt32(seconds * 1000)
        }))
    }

    /// Makes cards review cards with an interval of `intervalDays`, due today:
    /// young under 21 days, mature from 21 days.
    public func makeReviewCardsDueToday(_ cardIDs: [Int64], intervalDays: Int) async throws {
        // "N!" makes them review cards due in N days with an interval of N
        // days; moving them to today keeps that interval.
        try await modify(.setDueDate(.with {
            $0.cardIds = cardIDs
            $0.days = "\(intervalDays)!"
        }))
        try await makeDueToday(cardIDs)
    }

    /// Buries cards until tomorrow, as the learner can while studying.
    public func bury(_ cardIDs: [Int64]) async throws {
        try await modify(.buryOrSuspendCards(.with {
            $0.cardIds = cardIDs
            $0.mode = .buryUser
        }))
    }
}
