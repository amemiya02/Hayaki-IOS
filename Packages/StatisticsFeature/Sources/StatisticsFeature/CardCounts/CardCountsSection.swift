import Charts
import HayakiAppearance
import SwiftUI

/// A ring chart of how the cards divide between states, with each state's
/// count and share listed below it.
struct CardCountsSection: View {
    let counts: CardCounts
    @Environment(\.statisticsReportPeriod) private var reportPeriod
    @Binding var separateInactive: Bool
    @State private var angle: Int?

    private var selected: CardCounts.Entry? {
        guard let angle else { return nil }
        var start = 0
        return shownEntries.first { entry in
            start += entry.count
            return angle <= start
        }
    }

    var body: some View {
        Section {
            if reportPeriod == nil {
                Toggle(isOn: $separateInactive) { Text("Separate Suspended and Buried Cards", bundle: .module) }
            }
            if counts.isEmpty {
                Text("There are no cards here yet.", bundle: .module)
                    .foregroundStyle(.secondary)
            } else {
                chart
                ForEach(shownRows) { entry in
                    countRow(entry)
                }
            }
        } header: {
            StatisticsCardHeader(
                title: Text("Card Counts", bundle: .module),
                reading: counts.isEmpty ? nil : Text(
                    "\(counts.total, format: .number) cards, \(counts.fraction(.mature), format: .percent.precision(.fractionLength(0))) of them mature",
                    bundle: .module,
                    comment: "Card Counts card reading: all cards, and the share of mature cards."
                )
            )
        }
        .onChange(of: counts) { angle = nil }
    }

    private var chart: some View {
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
        .chartAngleSelection(value: $angle)
        .chartBackground { _ in
            VStack {
                Text(selected?.count ?? counts.total, format: .number)
                    .font(.title2.bold().monospacedDigit())
                Group {
                    if let selected {
                        Text(selected.state.title)
                    } else {
                        Text("Total", bundle: .module)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
        }
        .frame(height: 220)
        .padding(.vertical, 8)

    }

    private func countRow(_ entry: CardCounts.Entry) -> some View {
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

    private var shownRows: [CardCounts.Entry] {
        counts.entries.filter { separateInactive || ($0.state != .suspended && $0.state != .buried) }
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
    /// The state's colour from the design tokens' count meanings: New blue,
    /// Learning red and Due green, with the lighter shade for relearning and
    /// young cards. Inactive cards are gray.
    var color: Color {
        switch self {
        case .new: SemanticColor.new.color
        case .learning: SemanticColor.learning.color
        case .relearning: SemanticColor.learning.color.opacity(0.5)
        case .young: SemanticColor.due.color.opacity(0.5)
        case .mature: SemanticColor.due.color
        case .suspended: .gray
        case .buried: .gray.opacity(0.5)
        }
    }
}
