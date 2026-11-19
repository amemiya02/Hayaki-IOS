import CollectionStore
import StudyFeature
import SwiftUI

public struct CustomStudyScreen: View {
    @State private var model: CustomStudyModel
    @Environment(\.dismiss) private var dismiss
    let onStart: (StudyDeck) -> Void

    public init(store: CollectionStore, deckID: Int64, onStart: @escaping (StudyDeck) -> Void) {
        _model = State(initialValue: CustomStudyModel(store: store, deckID: deckID))
        self.onStart = onStart
    }

    public var body: some View {
        @Bindable var form = model
        NavigationStack {
            Form {
                if model.isLoaded {
                    Section {
                        Picker(selection: Binding(get: { model.choice }, set: model.choose)) {
                            ForEach(CustomStudyModel.Choice.allCases, id: \.self) { choice in
                                choice.title.tag(choice)
                            }
                        } label: {
                            Text("Study Type", bundle: .module)
                        }
                        TextField(value: $form.amount, format: .number.grouping(.never)) {
                            model.choice.amountTitle
                        }
                    } footer: {
                        switch model.choice {
                        case .extendNew:
                            Text("\(model.availableNew) new cards available.", bundle: .module)
                        case .extendReviews:
                            Text("\(model.availableReviews) review cards available.", bundle: .module)
                        default:
                            EmptyView()
                        }
                    }
                    if model.choice == .studyByTag {
                        Section {
                            Picker(selection: $form.cardSelection) {
                                ForEach(CustomStudyModel.CardSelection.allCases, id: \.rawValue) { cards in
                                    cards.title.tag(cards)
                                }
                            } label: {
                                Text("Cards", bundle: .module)
                            }
                            ForEach(model.tags, id: \.self) { tag in
                                Picker(selection: tagMode(for: tag)) {
                                    Text("Any", bundle: .module).tag(TagMode.any)
                                    Text("Include", bundle: .module).tag(TagMode.include)
                                    Text("Exclude", bundle: .module).tag(TagMode.exclude)
                                } label: {
                                    Text(verbatim: tag)
                                }
                            }
                        }
                    }
                }
                if model.isWorking {
                    ProgressView()
                }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                }
            }
            .disabled(model.isWorking)
            .navigationTitle(Text("Custom Study", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let deck = await model.start() {
                                onStart(deck)
                                dismiss()
                            }
                        }
                    } label: {
                        Text("Study", bundle: .module)
                    }
                    .disabled(!model.canStart)
                }
            }
        }
        .interactiveDismissDisabled(model.isWorking)
        .task { await model.load() }
    }

    private enum TagMode: Hashable { case any, include, exclude }

    private func tagMode(for tag: String) -> Binding<TagMode> {
        Binding {
            if model.includedTags.contains(tag) { return .include }
            if model.excludedTags.contains(tag) { return .exclude }
            return .any
        } set: { mode in
            model.includedTags.remove(tag)
            model.excludedTags.remove(tag)
            if mode == .include { model.includedTags.insert(tag) }
            if mode == .exclude { model.excludedTags.insert(tag) }
        }
    }
}

private extension CustomStudyModel.Choice {
    var title: Text {
        switch self {
        case .extendNew: Text("Increase Today's New Card Limit", bundle: .module)
        case .extendReviews: Text("Increase Today's Review Limit", bundle: .module)
        case .reviewForgotten: Text("Review Forgotten Cards", bundle: .module)
        case .reviewAhead: Text("Review Ahead", bundle: .module)
        case .previewNew: Text("Preview New Cards", bundle: .module)
        case .studyByTag: Text("Select Cards by State or Tag", bundle: .module)
        }
    }

    var amountTitle: Text {
        switch self {
        case .extendNew, .extendReviews: Text("Additional Cards", bundle: .module)
        case .reviewForgotten, .reviewAhead, .previewNew: Text("Days", bundle: .module)
        case .studyByTag: Text("Card Limit", bundle: .module)
        }
    }
}

private extension CustomStudyModel.CardSelection {
    var title: Text {
        switch self {
        case .due: Text("Due Cards", bundle: .module)
        case .new: Text("New Cards", bundle: .module)
        case .review: Text("Review Cards", bundle: .module)
        case .all: Text("All Cards", bundle: .module)
        case .UNRECOGNIZED: Text("Unknown Selection", bundle: .module)
        }
    }
}
