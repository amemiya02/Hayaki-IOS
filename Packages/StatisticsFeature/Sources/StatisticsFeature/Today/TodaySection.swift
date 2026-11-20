import HayakiAppearance
import SwiftUI

/// The summary of today's studying: reviews, time, correct rate and the
/// current streak as large numbers, then the details below them.
struct TodaySection: View {
    let today: TodaySummary
    let streak: StudyStreak

    init(graphs: StatisticsGraphs) {
        today = graphs.today
        streak = graphs.studyStreak
    }

    var body: some View {
        Section {
            figures
            if today.isEmpty {
                Text("No cards have been studied today.", bundle: .module)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                details
            }
        } header: {
            StatisticsCardHeader(title: Text("Today", bundle: .module))
        }
    }

    private var figures: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { figureViews }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    reviewsFigure
                    timeFigure
                }
                GridRow {
                    correctFigure
                    streakFigure
                }
            }
            VStack(alignment: .leading, spacing: 12) { figureViews }
        }
    }

    @ViewBuilder
    private var figureViews: some View {
        reviewsFigure
        timeFigure
        correctFigure
        streakFigure
    }

    private var reviewsFigure: some View {
        TodayFigure(label: Text("Reviews", bundle: .module)) {
            Text(today.reviews, format: .number)
        }
    }

    private var timeFigure: some View {
        TodayFigure(label: Text("Time", bundle: .module), unit: Text("min", bundle: .module, comment: "Unit after a number of minutes in the Today card.")) {
            Text(Int((Double(today.time.components.seconds) / 60).rounded()), format: .number)
        }
    }

    private var correctFigure: some View {
        TodayFigure(label: Text("Correct", bundle: .module)) {
            if let correct = today.correctFraction {
                Text(correct, format: .percent.precision(.fractionLength(0)))
            } else {
                Text(verbatim: "–")
            }
        }
    }

    private var streakFigure: some View {
        TodayFigure(
            label: Text("Streak", bundle: .module, comment: "Today card: the number of days in a row with reviews."),
            unit: Text("days", bundle: .module, comment: "Unit after the number of days in the study streak.")
        ) {
            if streak.isAtLeast {
                Text("\(streak.days, format: .number)+", bundle: .module, comment: "A streak at least this many days long, e.g. \"31+\".")
            } else {
                Text(streak.days, format: .number)
            }
        }
    }

    @ViewBuilder
    private var details: some View {
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

    private static let durationStyle = Duration.UnitsFormatStyle(
        allowedUnits: [.hours, .minutes, .seconds],
        width: .abbreviated,
        maximumUnitCount: 2
    )
}

/// One of the Today card's large numbers, with its label under it. The unit
/// is a separate `Text`, since SF Rounded has no Chinese or Japanese glyphs.
private struct TodayFigure<Value: View>: View {
    let label: Text
    var unit: Text?
    @ViewBuilder let value: () -> Value

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                value()
                    .font(.title.weight(.semibold))
                    .hayakiNumeric()
                if let unit {
                    unit
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            label
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
