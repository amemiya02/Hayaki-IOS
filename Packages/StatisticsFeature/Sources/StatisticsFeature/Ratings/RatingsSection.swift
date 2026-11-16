import Charts
import SwiftUI

/// A bar chart of how often each rating was chosen in the period, stacked by
/// the kind of card reviewed, with each kind's share of correct reviews below.
struct RatingsSection: View {
    let ratings: RatingCounts

    var body: some View {
        StatisticsSectionView(
            title: Text("Ratings", bundle: .module),
            emptyMessage: ratings.isEmpty ? Text("No reviews in this period.", bundle: .module) : nil
        ) {
            Chart(ratings.entries.filter { $0.count > 0 }) { entry in
                BarMark(
                    x: .value(Text("Rating", bundle: .module), entry.rating.title),
                    y: .value(Text("Reviews", bundle: .module), entry.count)
                )
                .foregroundStyle(by: .value(Text("Card", bundle: .module), entry.kind.title))
                .accessibilityLabel(Text("\(entry.rating.title), \(entry.kind.title)", bundle: .module))
                .accessibilityValue(Text(reviewsText(entry.count)))
            }
            .chartXScale(domain: Rating.allCases.map(\.title))
            .chartForegroundStyleScale(
                domain: ReviewedCardKind.allCases.map(\.title),
                range: ReviewedCardKind.allCases.map(\.color)
            )
            .chartLegend(position: .bottom)
            .frame(height: 220)
            .padding(.vertical, 8)

            ForEach(Rating.allCases, id: \.self) { rating in
                LabeledContent {
                    Text(
                        "\(ratings.count(rating), format: .number) (\(ratings.fraction(rating), format: .percent.precision(.fractionLength(0))))",
                        bundle: .module
                    )
                    .monospacedDigit()
                } label: {
                    Text(rating.title)
                }
            }
            ForEach(ReviewedCardKind.allCases, id: \.self) { kind in
                if let correct = ratings.correctFraction(of: kind) {
                    LabeledContent {
                        Text("\(correct, format: .percent.precision(.fractionLength(0))) of \(ratings.reviews(of: kind), format: .number)", bundle: .module)
                            .monospacedDigit()
                    } label: {
                        Text("\(kind.title) Correct", bundle: .module)
                    }
                }
            }
        }
    }

    private func reviewsText(_ count: Int) -> String {
        String(localized: "\(count) reviews", bundle: .module, comment: "VoiceOver value of a ratings bar: how many reviews it stands for.")
    }
}

extension ReviewedCardKind {
    /// The same colours as the card counts chart uses for these states.
    var color: Color {
        switch self {
        case .learning: CardState.learning.color
        case .young: CardState.young.color
        case .mature: CardState.mature.color
        }
    }
}
