import HayakiAppearance
import SwiftUI

/// Show Answer, or once the answer shows, the ratings with the interval each
/// would give. Both float in the same spot over the bottom of the card, so the
/// learner's thumb stays in one place.
struct AnswerBar: View {
    let card: StudyCard
    let showingAnswer: Bool
    let isAnswering: Bool
    let minimumPress: Double
    let cooldown: Duration
    let buttonHeight: Double
    let hideHardAndEasy: Bool
    let showsIntervals: Bool
    let onShowAnswer: () -> Void
    let onShortPress: () -> Void
    let onRate: (Rating) -> Void
    @State private var lastPress: ContinuousClock.Instant?
    @State private var rated: RatedPress?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            if showingAnswer {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ratingButtons
                        }
                    } else {
                        HStack(spacing: 8) { ratingButtons }
                    }
                }
                .disabled(isAnswering)
            } else {
                ReviewerPressButton(
                    minimumPress: minimumPress,
                    action: { guarded(onShowAnswer) },
                    onShortPress: onShortPress
                ) {
                    Text("Show Answer", bundle: .module)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: buttonHeight)
                }
                .answerBarStyle(prominent: true)
                .disabled(isAnswering)
                .accessibilityIdentifier("show-answer")
            }
        }
        .frame(minHeight: 60)
        .sensoryFeedback(trigger: rated) { _, press in press?.rating.feedback }
    }

    private var ratingButtons: some View {
        ForEach(hideHardAndEasy ? [.again, .good] : Rating.allCases, id: \.self) { rating in
            RatingButton(
                rating: rating, interval: showsIntervals ? card.intervals[rating] : nil, buttonHeight: buttonHeight
            ) {
                guarded {
                    rated = RatedPress(rating: rating)
                    onRate(rating)
                }
            }
        }
    }

    private func guarded(_ action: () -> Void) {
        let now = ContinuousClock.now
        guard lastPress.map({ now - $0 >= cooldown }) != false else { return }
        lastPress = now
        action()
    }
}

/// One press of a rating, so pressing the same rating on the next card
/// still gives feedback.
private struct RatedPress: Equatable {
    let id = UUID()
    let rating: Rating
}

extension Rating {
    /// The tap felt on rating: firmer for Again, lighter for Good and Easy.
    var feedback: SensoryFeedback {
        switch self {
        case .again: .impact(weight: .heavy)
        case .hard: .impact(weight: .medium)
        case .good, .easy: .impact(weight: .light)
        }
    }
}

private struct RatingButton: View {
    let rating: Rating
    let interval: String?
    let buttonHeight: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if let interval {
                    Text(interval)
                        .font(.caption.weight(.medium))
                        .hayakiNumeric()
                }
                rating.title
                    .font(.subheadline.weight(.semibold))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: buttonHeight)
        }
        .answerBarStyle(prominent: false)
        .tint(rating.semanticColor.color)
        .accessibilityLabel(rating.title)
        .accessibilityValue(Text(interval ?? ""))
        .accessibilityIdentifier("rating-\(rating)")
    }
}

private extension View {
    func answerBarStyle(prominent: Bool) -> some View {
        modifier(AnswerBarButtonStyle(prominent: prominent))
    }
}

/// Liquid Glass buttons, or solid ones when the learner turns on Reduce
/// Transparency.
private struct AnswerBarButtonStyle: ViewModifier {
    let prominent: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        switch (prominent, reduceTransparency) {
        case (true, false): content.buttonStyle(.glassProminent)
        case (false, false): content.buttonStyle(.glass)
        case (true, true): content.buttonStyle(.borderedProminent)
        case (false, true): content.buttonStyle(.bordered)
        }
    }
}

private struct ReviewerPressButton<Label: View>: View {
    let minimumPress: Double
    let action: () -> Void
    let onShortPress: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var held = false

    var body: some View {
        if minimumPress == 0 {
            Button(action: action, label: label)
        } else {
            Button {
                if held { held = false } else { onShortPress() }
            } label: {
                label()
            }
            .simultaneousGesture(LongPressGesture(minimumDuration: minimumPress).onEnded { _ in
                held = true
                action()
            })
                .accessibilityAction { action() }
        }
    }
}
