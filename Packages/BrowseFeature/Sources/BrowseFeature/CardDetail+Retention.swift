import Foundation

extension CardDetail {
    public struct RetentionPoint: Equatable, Sendable {
        public let date: Date
        public let probability: Double
        let reviewIndex: Int
    }

    /// Profiles the latest continuous run of FSRS reviews from the first
    /// learning event to the requested date.
    public func retentionPoints(at end: Date = .now, dayLimit: Int? = nil) -> [RetentionPoint] {
        guard memoryState != nil else { return [] }
        // The core lists newest reviews first. A reset or entry without a
        // memory state ends the run, as it does in Anki's Card Info.
        let reviews = history.prefix { review in
            review.memoryState != nil && (review.kind != .manual || review.recordedEase != 0)
        }.filter { review in
            switch review.kind {
            case .manual, .rescheduled: false
            case .filtered: review.recordedEase != 0
            default: true
            }
        }.reversed()
        guard let first = reviews.first else { return [] }

        let secondsPerDay = 86_400.0
        let lastDate = dayLimit.map { min(end, first.date.addingTimeInterval(Double($0) * secondsPerDay)) } ?? end
        let factor = pow(0.9, -1 / fsrsDecay) - 1
        var points: [RetentionPoint] = []
        let ordered = Array(reviews)
        for (index, review) in ordered.enumerated() where review.date <= lastDate {
            guard let stability = review.memoryState?.stabilityDays, stability > 0 else { continue }
            let nextDate = ordered.indices.contains(index + 1) ? ordered[index + 1].date : lastDate
            let segmentEnd = min(nextDate, lastDate)
            let duration = segmentEnd.timeIntervalSince(review.date)
            // More samples near the review capture the faster initial drop.
            let samples = 24
            for sample in 0...samples {
                let fraction = Double(sample) / Double(samples)
                let elapsed = duration * fraction * fraction
                let probability = pow(1 + factor * elapsed / (stability * secondsPerDay), -fsrsDecay)
                let date = sample == samples ? segmentEnd : review.date.addingTimeInterval(elapsed)
                points.append(RetentionPoint(date: date, probability: probability, reviewIndex: index))
            }
        }
        return points
    }

    var retentionHistoryDays: Int {
        guard let firstReview else { return 0 }
        return max(0, Int(Date.now.timeIntervalSince(firstReview) / 86_400))
    }
}
