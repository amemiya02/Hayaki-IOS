import SwiftUI

/// Shared preset limits and two levels of overrides for the deck.
struct DailyLimitsSection: View {
    @Bindable var model: DeckOptionsModel

    var body: some View {
        Section {
            NumberRow(value: $model.newCardsPerDay, identifier: "new-cards-per-day") {
                Text("New cards/day", bundle: .module)
            }
            NumberRow(value: $model.reviewsPerDay, identifier: "reviews-per-day") {
                Text("Maximum reviews/day", bundle: .module)
            }
            DisclosureGroup {
                LimitOverrideRow(value: $model.deckNewCardsLimit, suggested: model.newCardsPerDay, identifier: "deck-new-limit") {
                    Text("New cards/day", bundle: .module)
                }
                LimitOverrideRow(value: $model.deckReviewsLimit, suggested: model.reviewsPerDay, identifier: "deck-review-limit") {
                    Text("Maximum reviews/day", bundle: .module)
                }
            } label: {
                scopeLabel(Text("This deck", bundle: .module), active: model.deckNewCardsLimit != nil || model.deckReviewsLimit != nil)
            }
            DisclosureGroup {
                LimitOverrideRow(value: $model.todayNewCardsLimit, suggested: model.suggestedTodayNewCardsLimit, identifier: "today-new-limit") {
                    Text("New cards/day", bundle: .module)
                }
                LimitOverrideRow(value: $model.todayReviewsLimit, suggested: model.suggestedTodayReviewsLimit, identifier: "today-review-limit") {
                    Text("Maximum reviews/day", bundle: .module)
                }
            } label: {
                scopeLabel(Text("Today only", bundle: .module), active: model.todayNewCardsLimit != nil || model.todayReviewsLimit != nil)
            }
            Toggle(isOn: $model.newCardsIgnoreReviewLimit) {
                Text("New cards ignore review limit", bundle: .module)
            }
            Toggle(isOn: $model.applyAllParentLimits) {
                Text("Limits start from top", bundle: .module)
            }
        } header: {
            Text("Daily Limits", bundle: .module)
        } footer: {
            Text("The first two values are shared by every deck using this preset. Deck and today overrides affect this deck. Both switches apply to the whole collection.", bundle: .module)
        }
    }

    private func scopeLabel(_ title: Text, active: Bool) -> some View {
        LabeledContent {
            if active { Text("Override active", bundle: .module) }
        } label: {
            title
        }
    }
}

private struct LimitOverrideRow<Label: View>: View {
    @Binding var value: Int?
    let suggested: Int
    let identifier: String
    @ViewBuilder let label: Label

    var body: some View {
        Toggle(isOn: Binding {
            value != nil
        } set: { enabled in
            value = enabled ? suggested : nil
        }) {
            label
        }
        if value != nil {
            NumberRow(value: Binding {
                value ?? suggested
            } set: { value = $0 }, identifier: identifier) {
                Text("Limit", bundle: .module)
            }
        }
    }
}

/// Learning steps for new cards and relearning steps for forgotten reviews.
struct StepsSections: View {
    @Bindable var model: DeckOptionsModel

    var body: some View {
        Section {
            StepsRow(text: $model.learningSteps, isInvalid: model.learningStepsError != nil, identifier: "learning-steps") {
                Text("Learning steps", bundle: .module)
            }
        } header: {
            Text("New Cards", bundle: .module)
        } footer: {
            StepsFooter(error: model.learningStepsError) {
                Text("When a new card comes back while you learn it, such as 1m 10m 1d.", bundle: .module)
            }
        }
        Section {
            StepsRow(text: $model.relearningSteps, isInvalid: model.relearningStepsError != nil, identifier: "relearning-steps") {
                Text("Relearning steps", bundle: .module)
            }
        } header: {
            Text("Lapses", bundle: .module)
        } footer: {
            StepsFooter(error: model.relearningStepsError) {
                Text("When a forgotten review card comes back. Leave empty to skip relearning.", bundle: .module)
            }
        }
    }
}

/// The order in which new and review cards are shown.
struct DisplayOrderSection: View {
    @Bindable var model: DeckOptionsModel

    var body: some View {
        Section {
            Picker(selection: $model.newCardGatherOrder) {
                ForEach(NewCardGatherOrder.allCases, id: \.self) { order in
                    order.title.tag(order)
                }
            } label: {
                Text("New card gather order", bundle: .module)
            }
            Picker(selection: $model.newCardSortOrder) {
                ForEach(NewCardSortOrder.allCases, id: \.self) { order in
                    order.title.tag(order)
                }
            } label: {
                Text("New card sort order", bundle: .module)
            }
            Picker(selection: $model.newReviewMix) {
                ForEach(ReviewMix.allCases, id: \.self) { mix in
                    mix.title.tag(mix)
                }
            } label: {
                Text("New/review order", bundle: .module)
            }
            Picker(selection: $model.interdayLearningReviewMix) {
                ForEach(ReviewMix.allCases, id: \.self) { mix in
                    mix.title.tag(mix)
                }
            } label: {
                Text("Interday learning/review order", bundle: .module)
            }
            Picker(selection: $model.reviewSortOrder) {
                ForEach(ReviewSortOrder.allCases, id: \.self) { order in
                    order.title.tag(order)
                }
            } label: {
                Text("Review sort order", bundle: .module)
            }
        } header: {
            Text("Display Order", bundle: .module)
        }
    }
}

/// Whether other cards of the same note wait until the next day.
struct BuryingSection: View {
    @Bindable var model: DeckOptionsModel

    var body: some View {
        Section {
            Toggle(isOn: $model.buryNewSiblings) {
                Text("Bury new siblings", bundle: .module)
            }
            Toggle(isOn: $model.buryReviewSiblings) {
                Text("Bury review siblings", bundle: .module)
            }
            Toggle(isOn: $model.buryInterdayLearningSiblings) {
                Text("Bury interday learning siblings", bundle: .module)
            }
        } header: {
            Text("Burying", bundle: .module)
        } footer: {
            Text("When you study a card, other cards of the same note wait until the next day.", bundle: .module)
        }
    }
}

// MARK: Rows

struct NumberRow<Label: View>: View {
    @Binding var value: Int
    let identifier: String
    @ViewBuilder let label: Label
    /// The digits as typed. The model gets each number as it is typed: a
    /// number pad has no Return key to commit it before Save is tapped.
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        LabeledContent {
            TextField(text: $text, prompt: Text(value, format: .number)) { label }
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(identifier, isEnabled: !identifier.isEmpty)
                .monospacedDigit()
                // Room for four digits, leaving the rest to the label.
                .frame(maxWidth: 80)
                .focused($isFocused)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .onAppear { text = String(value) }
                .onChange(of: text) { _, typed in
                    if let number = Int(typed.filter(\.isASCII).filter(\.isNumber).prefix(9)) { value = number }
                }
                // Shows the number as the model holds it: limited to what
                // Anki accepts, or another preset's after switching.
                .onChange(of: value) { _, number in
                    if Int(text) != number { text = String(number) }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused { text = String(value) }
                }
        } label: {
            label
        }
    }
}

private struct StepsRow<Label: View>: View {
    @Binding var text: String
    let isInvalid: Bool
    let identifier: String
    @ViewBuilder let label: Label

    var body: some View {
        LabeledContent {
            TextField(text: $text, prompt: Text(verbatim: "1m 10m")) { label }
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(identifier)
                .autocorrectionDisabled()
                .foregroundStyle(isInvalid ? Color.red : Color.primary)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
                #endif
        } label: {
            label
        }
    }
}

private struct StepsFooter<Help: View>: View {
    let error: String?
    @ViewBuilder let help: Help

    var body: some View {
        if let error {
            Label {
                Text(verbatim: error)
            } icon: {
                Image(systemName: "exclamationmark.circle.fill")
            }
            .foregroundStyle(.red)
        } else {
            help
        }
    }
}

// MARK: Option names

extension NewCardGatherOrder {
    var title: Text {
        switch self {
        case .deck: Text("Deck", bundle: .module)
        case .deckThenRandomNotes: Text("Deck, then random notes", bundle: .module)
        case .lowestPosition: Text("Ascending position", bundle: .module)
        case .highestPosition: Text("Descending position", bundle: .module)
        case .randomNotes: Text("Random notes", bundle: .module)
        case .randomCards: Text("Random cards", bundle: .module)
        case .UNRECOGNIZED: Text("Other", bundle: .module)
        }
    }
}

extension NewCardSortOrder {
    var title: Text {
        switch self {
        case .template: Text("Card type, then order gathered", bundle: .module)
        case .noSort: Text("Order gathered", bundle: .module)
        case .templateThenRandom: Text("Card type, then random", bundle: .module)
        case .randomNoteThenTemplate: Text("Random note, then card type", bundle: .module)
        case .randomCard: Text("Random", bundle: .module)
        case .UNRECOGNIZED: Text("Other", bundle: .module)
        }
    }
}

extension ReviewMix {
    var title: Text {
        switch self {
        case .mixWithReviews: Text("Mix with reviews", bundle: .module)
        case .afterReviews: Text("Show after reviews", bundle: .module)
        case .beforeReviews: Text("Show before reviews", bundle: .module)
        case .UNRECOGNIZED: Text("Other", bundle: .module)
        }
    }
}

extension ReviewSortOrder {
    var title: Text {
        switch self {
        case .day: Text("Due date, then random", bundle: .module)
        case .dayThenDeck: Text("Due date, then deck", bundle: .module)
        case .deckThenDay: Text("Deck, then due date", bundle: .module)
        case .intervalsAscending: Text("Ascending intervals", bundle: .module)
        case .intervalsDescending: Text("Descending intervals", bundle: .module)
        case .easeAscending: Text("Ascending ease", bundle: .module)
        case .easeDescending: Text("Descending ease", bundle: .module)
        case .retrievabilityAscending: Text("Ascending retrievability", bundle: .module)
        case .retrievabilityDescending: Text("Descending retrievability", bundle: .module)
        case .relativeOverdueness: Text("Relative overdueness", bundle: .module)
        case .random: Text("Random", bundle: .module)
        case .added: Text("Order added", bundle: .module)
        case .reverseAdded: Text("Reverse order added", bundle: .module)
        case .UNRECOGNIZED: Text("Other", bundle: .module)
        }
    }
}
