import SwiftUI

struct FSRSSection: View {
    @Bindable var model: DeckOptionsModel
    @State private var editingWeights = false

    var body: some View {
        Section {
            Toggle(isOn: $model.fsrsEnabled) {
                Text("Enable FSRS", bundle: .module)
            }
            .disabled(model.isOptimizingFSRS)
        } header: {
            Text("FSRS", bundle: .module)
        } footer: {
            Text("FSRS estimates how well you remember each card, then uses your desired retention to schedule reviews. This setting applies to the whole collection.", bundle: .module)
        }

        if model.fsrsEnabled {
            retention
                .disabled(model.isOptimizingFSRS)
            parameters
        }
    }

    private var retention: some View {
        Section {
            RetentionStepper(value: $model.desiredRetention) {
                Text("Shared preset", bundle: .module)
            }
            Toggle(isOn: Binding {
                model.deckDesiredRetention != nil
            } set: { enabled in
                model.deckDesiredRetention = enabled ? model.desiredRetention : nil
            }) {
                Text("Override for this deck", bundle: .module)
            }
            if model.deckDesiredRetention != nil {
                RetentionStepper(value: Binding {
                    model.deckDesiredRetention ?? model.desiredRetention
                } set: { model.deckDesiredRetention = $0 }) {
                    Text("This deck", bundle: .module)
                }
            }
        } header: {
            Text("Desired Retention", bundle: .module)
        } footer: {
            let retention = model.deckDesiredRetention ?? model.desiredRetention
            if retention > 0.95 {
                Text("Above 95%, the number of reviews can increase sharply.", bundle: .module)
            } else if retention < 0.8 {
                Text("Below 80%, you may spend more time relearning forgotten cards.", bundle: .module)
            } else {
                Text("The target percentage of cards you remember when they are due.", bundle: .module)
            }
        }
    }

    private var parameters: some View {
        Section {
            Group {
                DisclosureGroup(isExpanded: $editingWeights) {
                    Text("Changing the weights manually can make scheduling less accurate.", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField(text: $model.fsrsParameterText, prompt: Text("Use default weights", bundle: .module), axis: .vertical) {
                        Text("Weights", bundle: .module)
                    }
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                } label: {
                    Text("Edit Weights", bundle: .module)
                }
                if let error = model.fsrsParameterError {
                    Text(verbatim: error).foregroundStyle(.red)
                }
                TextField(text: $model.fsrsParameterSearch, prompt: Text(verbatim: model.defaultFSRSParameterSearch)) {
                    Text("Search for optimization", bundle: .module)
                }
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                Toggle(isOn: $model.rescheduleWithFSRS) {
                    Text("Reschedule cards on change", bundle: .module)
                }
                Toggle(isOn: $model.fsrsHealthCheck) {
                    Text("Check parameter fit during optimization", bundle: .module)
                }
            }
            .disabled(model.isOptimizingFSRS)

            if model.isOptimizingFSRS {
                if let progress = model.fsrsProgress, progress.total > 0, progress.current < progress.total {
                    ProgressView(value: Double(progress.current), total: Double(progress.total)) {
                        Text("Optimizing with \(progress.reviews) reviews", bundle: .module)
                    }
                } else {
                    ProgressView {
                        if model.isCancellingFSRS {
                            Text("Cancelling…", bundle: .module)
                        } else if model.fsrsProgress?.total ?? 0 > 0 {
                            Text("Checking for improvement…", bundle: .module)
                        } else {
                            Text("Preparing optimization…", bundle: .module)
                        }
                    }
                }
                Button(role: .cancel) {
                    model.cancelFSRSOptimization()
                } label: {
                    Text("Cancel Optimization", bundle: .module)
                }
                .disabled(model.isCancellingFSRS)
            } else {
                Button {
                    Task { await model.optimizeFSRS() }
                } label: {
                    Text("Optimize Current Preset", bundle: .module)
                }
                .disabled(!model.canOptimizeFSRS)
                if !model.hasSavedFSRSPreset {
                    Text("Save preset changes before optimizing.", bundle: .module)
                        .foregroundStyle(.secondary)
                }
            }

            if let outcome = model.fsrsOutcome {
                outcomeMessage(outcome)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("FSRS Parameters", bundle: .module)
        } footer: {
            if model.rescheduleWithFSRS {
                Text("Saving may make many cards due immediately. Rescheduling applies across the collection and adds entries to review history.", bundle: .module)
            } else {
                Text("Optimization uses your review history. Save to apply new parameters.", bundle: .module)
            }
        }
    }

    @ViewBuilder
    private func outcomeMessage(_ outcome: DeckOptionsModel.FSRSOutcome) -> some View {
        switch outcome {
        case .optimized(let passed):
            Text("Parameters optimized. Save to apply them.", bundle: .module)
            healthCheck(passed)
        case .alreadyOptimal(let passed):
            Text("The current parameters already fit your review history.", bundle: .module)
            healthCheck(passed)
        case .insufficientHistory:
            Text("There is not enough review history for this search. Keep reviewing or broaden the search.", bundle: .module)
        case .cancelled:
            Text("Optimization cancelled. Your parameters were kept.", bundle: .module)
        case .failed(let message):
            Text(verbatim: message)
        }
    }

    @ViewBuilder
    private func healthCheck(_ passed: Bool?) -> some View {
        if passed == true {
            Text("The parameters fit your review history.", bundle: .module)
        } else if passed == false {
            Text("The parameters may fit your review history poorly.", bundle: .module)
        }
    }
}

struct RetentionStepper<Label: View>: View {
    @Binding var value: Float
    @ViewBuilder let label: Label

    var body: some View {
        Stepper(value: Binding {
            Int((value * 100).rounded())
        } set: { value = Float($0) / 100 }, in: 70...99) {
            LabeledContent {
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            } label: {
                label
            }
        }
    }
}
