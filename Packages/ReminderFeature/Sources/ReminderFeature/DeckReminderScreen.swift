import CollectionStore
import SwiftUI

public struct DeckReminderSettingsRow: View {
    let store: CollectionStore
    let profileID: UUID

    public init(store: CollectionStore, profileID: UUID) {
        self.store = store
        self.profileID = profileID
    }

    public var body: some View {
        NavigationLink {
            DeckReminderScreen(store: store, profileID: profileID)
        } label: {
            Label {
                Text("Deck Review Reminders", bundle: .module)
            } icon: {
                Image(systemName: "bell.badge")
            }
        }
        .accessibilityIdentifier("deck-review-reminders")
    }
}

public struct DeckReminderScreen: View {
    @State private var model: DeckReminderModel
    @State private var editing: DeckReminder?
    @Environment(\.scenePhase) private var scenePhase
    private let store: CollectionStore
    private let deckID: Int64?

    public init(store: CollectionStore, profileID: UUID, deckID: Int64? = nil) {
        self.store = store
        self.deckID = deckID
        _model = State(initialValue: DeckReminderModel(store: store, profileID: profileID))
    }

    public var body: some View {
        List {
            if model.notificationsRefused { NotificationsRefusedSection(forDeckReminders: true) }
            let rules = model.rules.filter { deckID == nil || $0.deckID == deckID }
            if rules.isEmpty {
                Text("No deck reminders", bundle: .module)
                    .foregroundStyle(.secondary)
            }
            ForEach(rules) { rule in
                let name = model.decks.first { $0.id == rule.deckID }?.name
                Button {
                    editing = rule
                } label: {
                    LabeledContent {
                        if rule.enabled, name != nil {
                            Text(rule.time, format: .dateTime.hour().minute())
                        } else {
                            Text("Off", bundle: .module)
                        }
                    } label: {
                        if let name { Text(verbatim: name) }
                        else { Text("Deck Unavailable", bundle: .module).foregroundStyle(.secondary) }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Task { await model.delete(rule.id) }
                    } label: {
                        Label {
                            Text("Delete Reminder", bundle: .module)
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle(Text("Deck Review Reminders", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let time = Calendar.current.dateComponents([.hour, .minute], from: .now)
                    if let id = deckID ?? model.decks.first?.id {
                        editing = DeckReminder(deckID: id, hour: time.hour ?? 9, minute: time.minute ?? 0)
                    }
                } label: {
                    Label {
                        Text("New Reminder", bundle: .module)
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
                .disabled(model.decks.isEmpty)
                .accessibilityIdentifier("add-deck-reminder")
            }
        }
        .sheet(item: $editing) { rule in
            DeckReminderEditor(rule: rule, model: model, allowsDeckSelection: deckID == nil)
        }
        .task {
            let changes = store.changes()
            await model.refresh()
            for await change in changes where change.contains(.deck) {
                await model.refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }
}

private struct DeckReminderEditor: View {
    @State var rule: DeckReminder
    let model: DeckReminderModel
    let allowsDeckSelection: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var threshold = ""

    private var minimum: Int? {
        guard let value = try? IntegerFormatStyle<Int>.number.grouping(.never).parseStrategy.parse(threshold),
              value >= 0
        else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if allowsDeckSelection {
                        Picker(selection: $rule.deckID) {
                            if !model.decks.contains(where: { $0.id == rule.deckID }) {
                                Text("Deck Unavailable", bundle: .module).tag(rule.deckID)
                            }
                            ForEach(model.decks) { deck in
                                Text(verbatim: deck.name).tag(deck.id)
                            }
                        } label: { Text("Deck", bundle: .module) }
                    }
                    Toggle(isOn: $rule.enabled) { Text("Enabled", bundle: .module) }
                    DatePicker(selection: Binding(
                        get: { rule.time },
                        set: {
                            let time = Calendar.current.dateComponents([.hour, .minute], from: $0)
                            rule.hour = time.hour ?? rule.hour
                            rule.minute = time.minute ?? rule.minute
                        }
                    ), displayedComponents: .hourAndMinute) {
                        Text("Time", bundle: .module)
                    }
                }
                Section {
                    TextField(text: $threshold) {
                        Text("Minimum Cards", bundle: .module)
                    }
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    Toggle(isOn: $rule.countNew) { Text("New Cards", bundle: .module) }
                    Toggle(isOn: $rule.countLearning) { Text("Learning Cards", bundle: .module) }
                    Toggle(isOn: $rule.countReview) { Text("Review Cards", bundle: .module) }
                } header: {
                    Text("Count Toward Minimum", bundle: .module)
                }
                Toggle(isOn: $rule.onlyWithoutReviews) {
                    Text("Only If I Haven’t Studied Today", bundle: .module)
                }
            }
            .navigationTitle(Text("Review Reminder", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Text("Cancel", bundle: .module) }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        guard let minimum else { return }
                        rule.minimumCards = minimum
                        isSaving = true
                        Task {
                            await model.save(rule)
                            dismiss()
                        }
                    } label: {
                        Text("Save", bundle: .module)
                    }
                    .disabled(isSaving || minimum == nil)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear { threshold = rule.minimumCards.formatted(.number.grouping(.never)) }
        }
    }
}
