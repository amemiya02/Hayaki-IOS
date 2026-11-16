import CollectionStore
import SwiftUI

/// A deck the learner chose to study.
public struct StudyDeck: Identifiable, Hashable, Sendable {
    public let id: Int64
    /// The deck's own name, shown at the top of the study screen.
    public let name: String

    public init(id: Int64, name: String) {
        self.id = id
        self.name = name
    }
}

extension View {
    /// Presents a full-screen study session over `deck` while it is set,
    /// and sets it back to nil when the learner closes the session.
    public func studySession(of deck: Binding<StudyDeck?>, store: CollectionStore) -> some View {
        #if os(iOS)
        fullScreenCover(item: deck) { deck in
            StudyScreen(store: store, deck: deck)
        }
        #else
        sheet(item: deck) { deck in
            StudyScreen(store: store, deck: deck)
        }
        #endif
    }
}

/// The study screen: the card fills the screen, with the counts above it and
/// Show Answer or the four rating buttons at the bottom, within thumb reach.
public struct StudyScreen: View {
    @State private var model: StudySessionModel
    private let deckName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(store: CollectionStore, deck: StudyDeck) {
        _model = State(initialValue: StudySessionModel(store: store, deckID: deck.id))
        deckName = deck.name
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            content
        }
        .background(Color.studyBackground.ignoresSafeArea())
        .task { await model.run() }
    }

    private var topBar: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(deckName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if model.state.card != nil {
                    StudyCountsView(counts: model.counts)
                }
            }
            .padding(.horizontal, 64)
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .contentShape(.rect)
                .accessibilityLabel(Text("Close", bundle: .module))
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var content: some View {
        // One view for both sides of every card, so the card's web view and
        // its page stay loaded for the whole session.
        if let card = model.state.card {
            studying(card, showingAnswer: model.state.answer != nil)
        } else {
            noCard
        }
    }

    @ViewBuilder
    private var noCard: some View {
        switch model.state {
        case .loading, .question, .answer:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .finished(let summary):
            FinishedView(summary: summary) { dismiss() }
        case .failed(let message):
            ContentUnavailableView {
                Label {
                    Text("Could Not Continue Studying", bundle: .module)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            } description: {
                Text(message)
            } actions: {
                Button {
                    dismiss()
                } label: {
                    Text("Close", bundle: .module)
                }
            }
        }
    }

    private func studying(_ card: StudyCard, showingAnswer: Bool) -> some View {
        VStack(spacing: 0) {
            cardView(CardDisplay(card, isAnswer: showingAnswer))
                // On an iPad, a readable column rather than a stretched line.
                .frame(maxWidth: horizontalSizeClass == .regular ? 820 : .infinity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            AnswerBar(card: card, showingAnswer: showingAnswer, isAnswering: model.isAnswering) {
                model.showAnswer()
            } onRate: { rating in
                Task { await model.answer(rating) }
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func cardView(_ display: CardDisplay) -> some View {
        #if os(iOS)
        CardWebView(display: display, zoom: dynamicTypeSize.cardZoom) {
            model.showAnswer()
        }
        // VoiceOver reads the card's own content inside the web view.
        .accessibilityIdentifier("card")
        #else
        Text(verbatim: display.html)
        #endif
    }
}

/// The new, learning and due counts left today, in Anki's blue, red and green.
private struct StudyCountsView: View {
    let counts: StudyCounts

    var body: some View {
        HStack(spacing: 14) {
            Text(counts.new, format: .number).foregroundStyle(.blue)
            Text(counts.learning, format: .number).foregroundStyle(.red)
            Text(counts.due, format: .number).foregroundStyle(.green)
        }
        .font(.subheadline.monospacedDigit().weight(.medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(
            "\(counts.new) new, \(counts.learning) learning, \(counts.due) due left",
            bundle: .module
        ))
        .accessibilityIdentifier("study-counts")
    }
}

/// Show Answer, or once the answer shows, the four ratings with the interval
/// each would give. Both fill the same strip at the bottom, so the learner's
/// thumb stays in one place.
private struct AnswerBar: View {
    let card: StudyCard
    let showingAnswer: Bool
    let isAnswering: Bool
    let onShowAnswer: () -> Void
    let onRate: (Rating) -> Void

    var body: some View {
        Group {
            if showingAnswer {
                HStack(spacing: 8) {
                    ForEach(Rating.allCases, id: \.self) { rating in
                        RatingButton(rating: rating, interval: card.intervals[rating]) {
                            onRate(rating)
                        }
                    }
                }
                .disabled(isAnswering)
            } else {
                Button(action: onShowAnswer) {
                    Text("Show Answer", bundle: .module)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityIdentifier("show-answer")
            }
        }
        .frame(minHeight: 60)
    }
}

private struct RatingButton: View {
    let rating: Rating
    let interval: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(interval)
                    .font(.caption.monospacedDigit().weight(.medium))
                rating.title
                    .font(.subheadline.weight(.semibold))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
        .tint(rating.color)
        .keyboardShortcut(rating.key, modifiers: [])
        .accessibilityLabel(rating.title)
        .accessibilityValue(Text(interval))
        .accessibilityIdentifier("rating-\(rating)")
    }
}

/// The end of the session, or a deck with nothing left today.
private struct FinishedView: View {
    let summary: SessionSummary
    let onDone: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("All Done for Today", bundle: .module)
            } icon: {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
            }
        } description: {
            VStack(spacing: 8) {
                if summary.reviewed > 0 {
                    Text("You reviewed \(summary.reviewed) cards in this session.", bundle: .module)
                } else {
                    Text("This deck has nothing left to study today.", bundle: .module)
                }
                if summary.learningLaterToday > 0 {
                    Text("\(summary.learningLaterToday) learning cards come due later today.", bundle: .module)
                }
                if summary.reviewed > 0, !summary.studiedToday.isEmpty {
                    Text(summary.studiedToday.replacingOccurrences(of: "\n", with: " "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } actions: {
            Button(action: onDone) {
                Text("Done", bundle: .module)
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }
}

extension Rating {
    var title: Text {
        switch self {
        case .again: Text("Again", bundle: .module, comment: "Rating: the learner did not recall the card.")
        case .hard: Text("Hard", bundle: .module, comment: "Rating: recalled with serious difficulty.")
        case .good: Text("Good", bundle: .module, comment: "Rating: recalled after some thought.")
        case .easy: Text("Easy", bundle: .module, comment: "Rating: recalled at once.")
        }
    }

    /// Anki's colours for the ratings.
    var color: Color {
        switch self {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }

    /// As in Anki, 1 to 4 rate from the keyboard.
    var key: KeyEquivalent {
        switch self {
        case .again: "1"
        case .hard: "2"
        case .good: "3"
        case .easy: "4"
        }
    }
}

private extension Color {
    static var studyBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}

private extension DynamicTypeSize {
    /// How much larger or smaller than at the default text size the card is
    /// drawn, so cards follow the learner's text size like the rest of the app.
    var cardZoom: CGFloat {
        switch self {
        case .xSmall: 0.82
        case .small: 0.88
        case .medium: 0.94
        case .large: 1
        case .xLarge: 1.12
        case .xxLarge: 1.24
        case .xxxLarge: 1.36
        case .accessibility1: 1.6
        case .accessibility2: 1.9
        case .accessibility3: 2.2
        case .accessibility4: 2.6
        case .accessibility5: 3
        @unknown default: 1
        }
    }
}
