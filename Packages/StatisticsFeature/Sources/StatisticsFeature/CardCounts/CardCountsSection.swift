import Charts
import SwiftUI

/// A ring chart of how the cards divide between states, with each state's
/// count and share listed below it.
struct CardCountsSection: View {
    let counts: CardCounts

    var body: some View {
        StatisticsSectionView(
            title: Text("Card Counts", bundle: .module),
            emptyMessage: counts.isEmpty ? Text("There are no cards here yet.", bundle: .module) : nil
        ) {
            Chart(shownEntries) { entry in
                SectorMark(
                    angle: .value(Text("Cards", bundle: .module), entry.count),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                .cornerRadius(3)
                .foregroundStyle(by: .value(Text("State", bundle: .module), entry.state.title))
                .accessibilityLabel(entry.state.title)
                .accessibilityValue(Text(accessibilityValue(entry)))
            }
            .chartForegroundStyleScale(
                domain: shownEntries.map(\.state.title),
                range: shownEntries.map(\.state.color)
            )
            .chartLegend(.hidden)
            .chartBackground { _ in
                VStack {
                    Text(counts.total, format: .number)
                        .font(.title2.bold().monospacedDigit())
                    Text("Total", bundle: .module)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
            }
            .frame(height: 220)
            .padding(.vertical, 8)

            ForEach(counts.entries) { entry in
                LabeledContent {
                    Text(
                        "\(entry.count, format: .number) (\(counts.fraction(entry.state), format: .percent.precision(.fractionLength(0))))",
                        bundle: .module
                    )
                    .monospacedDigit()
                } label: {
                    Label {
                        Text(entry.state.title)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(entry.state.color)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    /// Only states that have cards get a slice.
    private var shownEntries: [CardCounts.Entry] {
        counts.entries.filter { $0.count > 0 }
    }

    private func accessibilityValue(_ entry: CardCounts.Entry) -> String {
        String(
            localized: "\(entry.count) cards, \(counts.fraction(entry.state), format: .percent.precision(.fractionLength(0)))",
            bundle: .module,
            comment: "VoiceOver value of a card counts slice: the number of cards and their share."
        )
    }
}

extension CardState {
    /// The state's colour, close to the colours Anki's own statistics use.
    var color: Color {
        switch self {
        case .new: .blue
        case .learning: .orange
        case .young: .mint
        case .mature: .green
        case .suspended: .yellow
        case .buried: .gray
        }
    }
}
