import CollectionStore
import SwiftUI

/// Deck options presented from the deck list. Edits are applied when saved.
public struct DeckOptionsScreen: View {
    @State private var model: DeckOptionsModel
    @State private var isSaving = false
    @State private var confirmingDiscard = false
    @Environment(\.dismiss) private var dismiss

    public init(store: CollectionStore, deckID: Int64) {
        _model = State(initialValue: DeckOptionsModel(store: store, deckID: deckID))
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("Deck Options", bundle: .module))
                .navigationSubtitle(Text(verbatim: model.deckName))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbar }
        }
        .interactiveDismissDisabled(model.hasChanges || model.isOptimizingFSRS)
        .onDisappear { model.cancelFSRSOptimization() }
        .task {
            // Only the first time: loading again would discard edits.
            if model.state == .loading { await model.load() }
        }
        .alert(
            Text("Could Not Save Deck Options", bundle: .module),
            isPresented: Binding { model.saveError != nil && !isSaving } set: { _ in model.dismissSaveError() }
        ) {
            Button(role: .cancel) {} label: { Text("OK", bundle: .module) }
        } message: {
            Text(verbatim: model.saveError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label {
                    Text("Could Not Show Deck Options", bundle: .module)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            } description: {
                Text(verbatim: message)
            } actions: {
                Button {
                    Task { await model.load() }
                } label: {
                    Text("Try Again", bundle: .module)
                }
            }
        case .loaded:
            Form {
                Group {
                    PresetSection(model: model) { save(applyingToSubdecks: true) }
                    DailyLimitsSection(model: model)
                    StepsSections(model: model)
                    DisplayOrderSection(model: model)
                }
                .disabled(model.isOptimizingFSRS)
                FSRSSection(model: model)
                Group {
                    BuryingSection(model: model)
                    AudioSection(model: model)
                    TimerSection(model: model)
                    AutoAdvanceSection(model: model)
                    EasyDaysSection(model: model)
                    AdvancedSchedulingSection(model: model)
                    Section {
                        Link(destination: URL(string: "https://docs.ankiweb.net/deck-options.html")!) {
                            Text("Deck Options Help", bundle: .module)
                        }
                    }
                }
                .disabled(model.isOptimizingFSRS)
            }
            .disabled(isSaving)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                if model.hasChanges { confirmingDiscard = true } else { dismiss() }
            } label: {
                Text("Cancel", bundle: .module)
            }
            .disabled(model.isOptimizingFSRS || isSaving)
            .confirmationDialog(
                Text("Discard your changes to these deck options?", bundle: .module),
                isPresented: $confirmingDiscard,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    dismiss()
                } label: {
                    Text("Discard Changes", bundle: .module)
                }
                Button(role: .cancel) {} label: {
                    Text("Keep Editing", bundle: .module)
                }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView()
            } else {
                Button {
                    save()
                } label: {
                    Text("Save", bundle: .module)
                }
                .disabled(!model.hasChanges || !model.canSave)
            }
        }
    }

    private func save(applyingToSubdecks: Bool = false) {
        isSaving = true
        Task {
            let saved = await model.save(applyingToSubdecks: applyingToSubdecks)
            isSaving = false
            if saved { dismiss() }
        }
    }
}
