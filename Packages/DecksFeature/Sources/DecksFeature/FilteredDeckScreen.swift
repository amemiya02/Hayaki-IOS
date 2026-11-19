import CollectionStore
import SwiftUI

struct FilteredDeckScreen: View {
    @State private var model: FilteredDeckModel
    @Environment(\.dismiss) private var dismiss
    private let newDeck: Bool

    init(store: CollectionStore, deckID: Int64?) {
        newDeck = deckID == nil
        _model = State(initialValue: FilteredDeckModel(store: store, deckID: deckID))
    }

    var body: some View {
        @Bindable var editor = model
        NavigationStack {
            Form {
                if model.isLoaded {
                    Section {
                        TextField(text: $editor.name) {
                            Text("Name", bundle: .module)
                        }
                    }
                    Section {
                        FilterFields(filter: $editor.primary)
                    } header: {
                        Text("Filter", bundle: .module)
                    }
                    Section {
                        Toggle(isOn: Binding(get: { model.secondary != nil }, set: { enabled in
                            model.secondary = enabled ? FilteredDeckFilter() : nil
                        })) {
                            Text("Second Filter", bundle: .module)
                        }
                        if let secondary = Binding($editor.secondary) {
                            FilterFields(filter: secondary)
                        }
                    }
                    Section {
                        Toggle(isOn: $editor.reschedule) {
                            Text("Reschedule Based on Answers", bundle: .module)
                        }
                        if !model.reschedule {
                            TextField(value: $editor.previewAgainSeconds, format: .number.grouping(.never)) {
                                Text("Again Delay in Seconds", bundle: .module)
                            }
                            TextField(value: $editor.previewHardSeconds, format: .number.grouping(.never)) {
                                Text("Hard Delay in Seconds", bundle: .module)
                            }
                            TextField(value: $editor.previewGoodSeconds, format: .number.grouping(.never)) {
                                Text("Good Delay in Seconds", bundle: .module)
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
            .navigationTitle(newDeck ? Text("New Filtered Deck", bundle: .module) : Text("Filtered Deck Options", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: {
                        Text("Cancel", bundle: .module)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if await model.build() != nil { dismiss() }
                        }
                    } label: {
                        Text("Build", bundle: .module)
                    }
                    .disabled(!model.canBuild)
                }
            }
        }
        .interactiveDismissDisabled(model.isWorking)
        .task { await model.load() }
    }
}

private struct FilterFields: View {
    @Binding var filter: FilteredDeckFilter

    var body: some View {
        TextField(text: $filter.search) {
            Text("Search", bundle: .module)
        }
        TextField(value: $filter.limit, format: .number.grouping(.never)) {
            Text("Card Limit", bundle: .module)
        }
        Picker(selection: $filter.order) {
            ForEach(FilteredDeckFilter.Order.allCases, id: \.rawValue) { order in
                order.title.tag(order)
            }
        } label: {
            Text("Order", bundle: .module)
        }
    }
}

private extension FilteredDeckFilter.Order {
    var title: Text {
        switch self {
        case .oldestReviewedFirst: Text("Oldest Review First", bundle: .module)
        case .random: Text("Random", bundle: .module)
        case .intervalsAscending: Text("Increasing Intervals", bundle: .module)
        case .intervalsDescending: Text("Decreasing Intervals", bundle: .module)
        case .lapses: Text("Most Lapses", bundle: .module)
        case .added: Text("Oldest Added First", bundle: .module)
        case .due: Text("Due Date", bundle: .module)
        case .reverseAdded: Text("Newest Added First", bundle: .module)
        case .retrievabilityAscending: Text("Lowest Retrievability First", bundle: .module)
        case .retrievabilityDescending: Text("Highest Retrievability First", bundle: .module)
        case .relativeOverdueness: Text("Relative Overdueness", bundle: .module)
        case .UNRECOGNIZED: Text("Unknown Order", bundle: .module)
        }
    }
}
