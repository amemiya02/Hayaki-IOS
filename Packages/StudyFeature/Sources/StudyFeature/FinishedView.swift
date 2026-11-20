import Charts
import HayakiAppearance
import SwiftUI

/// The end of the session, or a deck with nothing left today: a header, the
/// session's figures, when studying can go on, the actions that apply and Done.
struct FinishedView: View {
    let summary: SessionSummary
    let onUnbury: () -> Void
    let onRebuild: () -> Void
    let onOptions: (() -> Void)?
    let onCustomStudy: (() -> Void)?
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var appeared = false

    var body: some View {
        List {
            Section {
                header
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if summary.reviewed > 0 {
                Section {
                    SessionCard(summary: summary)
                }
            }

            if summary.nextLearningAt != nil || showsNextDay {
                Section {
                    if let nextLearningAt = summary.nextLearningAt {
                        let time = nextLearningAt.formatted(date: .omitted, time: .shortened)
                        Label {
                            Text("Next learning card \(time)", bundle: .module)
                        } icon: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                    }
                    if showsNextDay {
                        Label {
                            Text("New study day \(Self.relativeDay(summary.nextDayStartsAt))", bundle: .module)
                        } icon: {
                            Image(systemName: "sunrise")
                        }
                    }
                }
            }

            if hasActions {
                Section {
                    if let onCustomStudy {
                        actionRow("wand.and.stars", action: onCustomStudy) {
                            Text("Custom Study", bundle: .module)
                        }
                    }
                    if let onOptions {
                        actionRow("gearshape", action: onOptions) {
                            Text("Deck Options", bundle: .module)
                        }
                    }
                    if summary.hasBuried {
                        actionRow("arrow.uturn.up", action: onUnbury) {
                            Text("Unbury Cards", bundle: .module)
                        }
                    }
                    if summary.isFiltered {
                        actionRow("arrow.clockwise", action: onRebuild) {
                            Text("Rebuild Filtered Deck", bundle: .module)
                        }
                    }
                }
            }

            // At accessibility text sizes a pinned button would cover most
            // of the screen, so Done ends the list instead.
            if !pinsDone {
                Section {
                    doneButton
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            if pinsDone {
                doneButton
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        // On iPad, the same centered readable column as the study card.
        .frame(maxWidth: horizontalSizeClass == .regular ? StudyScreen.readableCardWidth : .infinity)
        .frame(maxWidth: .infinity)
        .hayakiBackground(.grouped)
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear { appeared = true }
    }

    private var pinsDone: Bool {
        !dynamicTypeSize.isAccessibilitySize
    }

    private var doneButton: some View {
        Button(action: onDone) {
            Text("Done", bundle: .module)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .hayakiProminentLabel()
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: summary.reason == .done ? "checkmark.seal.fill" : "clock.fill")
                .font(.system(size: 64))
                .foregroundStyle(summary.reason == .done ? Color.green : Color.secondary)
                .symbolEffect(.bounce, value: reduceMotion ? false : appeared)
                .accessibilityHidden(true)
            title
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if summary.reviewed == 0, summary.reason == .done {
                Group {
                    if summary.isFiltered {
                        Text("This filtered deck is finished. Rebuild it to look for more cards.", bundle: .module)
                    } else {
                        Text("This deck has nothing left to study today.", bundle: .module)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var title: Text {
        switch summary.reason {
        case .dailyLimit: Text("Daily Limit Reached", bundle: .module)
        case .learningLater: Text("More Cards Later Today", bundle: .module)
        case .buried: Text("Cards Buried for Today", bundle: .module)
        case .done: Text("All Done for Today", bundle: .module)
        }
    }

    private var showsNextDay: Bool {
        summary.dailyLimitReached || summary.hasBuried
    }

    private var hasActions: Bool {
        onCustomStudy != nil || onOptions != nil || summary.hasBuried || summary.isFiltered
    }

    private func actionRow(
        _ systemImage: String,
        action: @escaping () -> Void,
        @ViewBuilder title: () -> Text
    ) -> some View {
        Button(action: action) {
            Label {
                title()
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }

    /// "Tomorrow, 4:00 AM", in the learner's language.
    static func relativeDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }
}

/// The cards reviewed and time spent in the session, with the ratings given.
private struct SessionCard: View {
    let summary: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                figure(Text(summary.reviewed, format: .number)) {
                    Text("Reviewed", bundle: .module, comment: "Under the number of cards reviewed in the session.")
                }
                Spacer()
                figure(Text(Self.clock(summary.timeSpent))) {
                    Text("Time", bundle: .module, comment: "Under the time spent studying in the session.")
                }
            }
            RatingBreakdownBar(ratings: summary.ratings)
        }
        .padding(.vertical, 8)
    }

    private func figure(_ value: Text, @ViewBuilder label: () -> Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            value
                .font(.largeTitle.weight(.semibold))
                .hayakiNumeric()
            label()
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// "3:25", or "1:03:25" past an hour: digits only, for SF Rounded.
    static func clock(_ duration: Duration) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern = duration >= .seconds(3600) ? .hourMinuteSecond : .minuteSecond
        return duration.formatted(.time(pattern: pattern))
    }
}

/// One stacked bar of the session's Again, Hard, Good and Easy ratings, with
/// the counts below it.
private struct RatingBreakdownBar: View {
    let ratings: RatingBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(Rating.allCases.filter { ratings[$0] > 0 }, id: \.self) { rating in
                BarMark(x: .value(Text("Reviewed", bundle: .module), ratings[rating]))
                    .foregroundStyle(rating.semanticColor.color)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartXScale(domain: 0...max(ratings.total, 1))
            .clipShape(.capsule)
            .frame(height: 10)
            .accessibilityHidden(true)

            // Side by side when they fit, one under another at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { legend }
                VStack(alignment: .leading, spacing: 4) { legend }
            }
        }
    }

    private var legend: some View {
        ForEach(Rating.allCases, id: \.self) { rating in
            HStack(spacing: 4) {
                Circle()
                    .fill(rating.semanticColor.color)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                rating.title
                Text(ratings[rating], format: .number)
                    .hayakiNumeric()
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
            .fixedSize()
            .accessibilityElement(children: .combine)
        }
    }
}
