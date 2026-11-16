import SwiftUI

/// The summary of today's studying.
struct TodaySection: View {
    let today: TodaySummary

    var body: some View {
        StatisticsSectionView(
            title: Text("Today", bundle: .module),
            emptyMessage: today.isEmpty ? Text("No cards have been studied today.", bundle: .module) : nil
        ) {
            LabeledContent {
                Text(today.reviews, format: .number)
            } label: {
                Text("Reviews", bundle: .module)
            }
            LabeledContent {
                Text(today.time.formatted(Self.durationStyle))
            } label: {
                Text("Time", bundle: .module)
            }
            if let average = today.averageTime {
                LabeledContent {
                    Text(average.formatted(Self.durationStyle))
                } label: {
                    Text("Average per Review", bundle: .module)
                }
            }
            LabeledContent {
                Text(today.againCount, format: .number)
            } label: {
                Text("Again", bundle: .module)
            }
            if let correct = today.correctFraction {
                LabeledContent {
                    Text(correct, format: .percent.precision(.fractionLength(0)))
                } label: {
                    Text("Correct", bundle: .module)
                }
            }
            LabeledContent {
                Text(
                    "\(today.learningReviews, format: .number) learning, \(today.reviewReviews, format: .number) review, \(today.relearningReviews, format: .number) relearning, \(today.filteredReviews, format: .number) filtered",
                    bundle: .module
                )
                .multilineTextAlignment(.trailing)
            } label: {
                Text("By Kind", bundle: .module)
            }
            if let matureCorrect = today.matureCorrectFraction {
                LabeledContent {
                    Text("\(today.matureCorrect, format: .number) of \(today.matureReviews, format: .number) (\(matureCorrect, format: .percent.precision(.fractionLength(0))))", bundle: .module)
                } label: {
                    Text("Mature Cards Correct", bundle: .module)
                }
            }
        }
    }

    private static let durationStyle = Duration.UnitsFormatStyle(
        allowedUnits: [.hours, .minutes, .seconds],
        width: .abbreviated,
        maximumUnitCount: 2
    )
}
