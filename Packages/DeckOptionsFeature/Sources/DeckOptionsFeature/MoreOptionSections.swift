import SwiftUI

struct TimerSection: View {
    @Bindable var model: DeckOptionsModel

    var body: some View {
        Section {
            NumberRow(value: $model.maximumAnswerSeconds, identifier: "maximum-answer-seconds") {
                Text("Maximum answer seconds", bundle: .module)
            }
            .restorePresetDefault(model, \.capAnswerTimeToSecs)
            Toggle(isOn: $model.showAnswerTimer) {
                Text("Show on-screen timer", bundle: .module)
            }
            .restorePresetDefault(model, \.showTimer)
            Toggle(isOn: $model.stopTimerOnAnswer) {
                Text("Stop timer when showing answer", bundle: .module)
            }
            .restorePresetDefault(model, \.stopTimerOnAnswer)
        } header: {
            Text("Timer", bundle: .module)
        }
    }
}

struct AudioSection: View {
    @Bindable var model: DeckOptionsModel

    var body: some View {
        Section {
            Toggle(isOn: $model.automaticallyPlayAudio) {
                Text("Play audio automatically", bundle: .module)
            }
            .restorePresetDefault(model, \.disableAutoplay)
            Toggle(isOn: $model.skipQuestionAudioWhenReplayingAnswer) {
                Text("Skip question audio when replaying answer", bundle: .module)
            }
            .restorePresetDefault(model, \.skipQuestionWhenReplayingAnswer)
        } header: {
            Text("Audio", bundle: .module)
        }
    }
}

struct AutoAdvanceSection: View {
    @Bindable var model: DeckOptionsModel

    var body: some View {
        Section {
            DecimalOptionRow(value: $model.secondsToShowQuestion) {
                Text("Seconds to show question", bundle: .module)
            }
            .restorePresetDefault(model, \.secondsToShowQuestion)
            DecimalOptionRow(value: $model.secondsToShowAnswer) {
                Text("Seconds to show answer", bundle: .module)
            }
            .restorePresetDefault(model, \.secondsToShowAnswer)
            Toggle(isOn: $model.waitForAudio) {
                Text("Wait for audio", bundle: .module)
            }
            .restorePresetDefault(model, \.waitForAudio)
            Picker(selection: $model.questionAction) {
                ForEach(AutoAdvanceQuestionAction.allCases, id: \.self) { choice in
                    choice.title.tag(choice)
                }
            } label: {
                Text("Question action", bundle: .module)
            }
            .restorePresetDefault(model, \.questionAction)
            Picker(selection: $model.answerAction) {
                ForEach(AutoAdvanceAnswerAction.allCases, id: \.self) { choice in
                    choice.title.tag(choice)
                }
            } label: {
                Text("Answer action", bundle: .module)
            }
            .restorePresetDefault(model, \.answerAction)
        } header: {
            Text("Auto Advance", bundle: .module)
        } footer: {
            Text("A delay of zero disables the timed action for that side.", bundle: .module)
        }
    }
}

struct EasyDaysSection: View {
    @Bindable var model: DeckOptionsModel

    var body: some View {
        Section {
            EasyDaysRows(values: $model.easyDaysPercentages)
        } header: {
            Text("Easy Days", bundle: .module)
        } footer: {
            Text("Space future reviews away from days with less study time.", bundle: .module)
        }
    }
}

struct AdvancedSchedulingSection: View {
    @Bindable var model: DeckOptionsModel

    var body: some View {
        Section {
            NumberRow(value: $model.maximumReviewInterval, identifier: "maximum-review-interval") {
                Text("Maximum interval (days)", bundle: .module)
            }
            .restorePresetDefault(model, \.maximumReviewInterval)
            if model.fsrsEnabled {
                DecimalOptionRow(value: $model.historicalRetention, percentage: true) {
                    Text("Historical retention", bundle: .module)
                }
                .restorePresetDefault(model, \.historicalRetention)
                Toggle(isOn: Binding {
                    model.ignoreFSRSHistoryBefore != nil
                } set: { enabled in
                    model.ignoreFSRSHistoryBefore = enabled ? Calendar.current.startOfDay(for: .now) : nil
                }) {
                    Text("Ignore reviews before a date", bundle: .module)
                }
                if model.ignoreFSRSHistoryBefore != nil {
                    DatePicker(selection: Binding {
                        model.ignoreFSRSHistoryBefore ?? .now
                    } set: {
                        model.ignoreFSRSHistoryBefore = $0
                    }, in: ...Date.now, displayedComponents: .date) {
                        Text("Earliest review date", bundle: .module)
                    }
                }
            } else {
                DecimalOptionRow(value: $model.initialEase, percentage: true) {
                    Text("Starting ease", bundle: .module)
                }
                .restorePresetDefault(model, \.initialEase)
                DecimalOptionRow(value: $model.easyMultiplier, percentage: true) {
                    Text("Easy bonus", bundle: .module)
                }
                .restorePresetDefault(model, \.easyMultiplier)
                DecimalOptionRow(value: $model.intervalMultiplier, percentage: true) {
                    Text("Interval modifier", bundle: .module)
                }
                .restorePresetDefault(model, \.intervalMultiplier)
                DecimalOptionRow(value: $model.hardMultiplier, percentage: true) {
                    Text("Hard interval", bundle: .module)
                }
                .restorePresetDefault(model, \.hardMultiplier)
                DecimalOptionRow(value: $model.lapseMultiplier, percentage: true) {
                    Text("New interval", bundle: .module)
                }
                .restorePresetDefault(model, \.lapseMultiplier)
            }
        } header: {
            Text("Advanced Scheduling", bundle: .module)
        }
        Section {
            DisclosureGroup {
                TextEditor(text: $model.customScheduling)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .accessibilityLabel(Text("Custom scheduling code", bundle: .module))
                    .frame(minHeight: 140)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } label: {
                Text("Custom Scheduling", bundle: .module)
            }
            .offerOptionDefault { model.customScheduling = "" }
        } footer: {
            Text("Custom scheduling is a collection-wide setting.", bundle: .module)
        }
    }
}

private struct DecimalOptionRow<Label: View>: View {
    @Binding var value: Float
    var percentage = false
    @ViewBuilder let label: Label
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private var scale: Float { percentage ? 100 : 1 }
    private var format: FloatingPointFormatStyle<Float> {
        .number.grouping(.never).precision(.fractionLength(0...2))
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 4) {
                TextField(text: $draft) { label }
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 90)
                    .focused($isFocused)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                if percentage { Text(verbatim: "%") }
            }
            .onAppear { updateDraft() }
            .onChange(of: draft) { _, draft in
                if isFocused, let number = try? format.parseStrategy.parse(draft), number.isFinite {
                    value = number / scale
                }
            }
            .onChange(of: value) { _, _ in
                if !isFocused { updateDraft() }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { updateDraft() }
            }
        } label: {
            label
        }
    }

    private func updateDraft() {
        draft = format.format(value * scale)
    }
}

private extension AutoAdvanceQuestionAction {
    var title: Text {
        switch self {
        case .showAnswer: Text("Show answer", bundle: .module)
        case .showReminder: Text("Show reminder", bundle: .module)
        case .UNRECOGNIZED: Text("Other", bundle: .module)
        }
    }
}

private extension AutoAdvanceAnswerAction {
    var title: Text {
        switch self {
        case .buryCard: Text("Bury card", bundle: .module)
        case .answerAgain: Text("Answer Again", bundle: .module)
        case .answerHard: Text("Answer Hard", bundle: .module)
        case .answerGood: Text("Answer Good", bundle: .module)
        case .showReminder: Text("Show reminder", bundle: .module)
        case .UNRECOGNIZED: Text("Other", bundle: .module)
        }
    }
}
