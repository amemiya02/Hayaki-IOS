import AnkiCore
import AnkiProto
import CollectionStore
import HayakiAppearance
import SwiftUI

/// Settings shared by the reviewer and the app's More screen.
public struct ReviewerSettingsScreen: View {
    let store: CollectionStore?
    @State private var preferences = ReviewerPreferences.load()
    @State private var side: ReviewerSide = .question
    @State private var selectingInput = false

    public init(store: CollectionStore? = nil) {
        self.store = store
    }

    public var body: some View {
        Form {
            if let store {
                SchedulingPreferenceSection(store: store)
                ReviewerCollectionSettings(store: store)
            }
            Section(reviewerLocalized("Studying")) {
                Toggle(reviewerLocalized("Keep Screen On"), isOn: $preferences.keepScreenOn)
                Toggle(reviewerLocalized("Center Card Vertically"), isOn: $preferences.centerVertically)
                Toggle(reviewerLocalized("Show Current Card’s Deck"), isOn: $preferences.showDeckTitle)
                Toggle(reviewerLocalized("Show Study Progress"), isOn: $preferences.showProgress)
                Toggle(reviewerLocalized("Show Rating Feedback"), isOn: $preferences.showFeedback)
                Toggle(reviewerLocalized("Show Answer Buttons"), isOn: $preferences.showAnswerButtons)
                Toggle(reviewerLocalized("Hide Hard and Easy"), isOn: $preferences.hideHardAndEasy)
                Toggle(reviewerLocalized("Show Card Frame"), isOn: $preferences.cardFrame)
                Toggle(reviewerLocalized("Hide Status Bar"), isOn: $preferences.hideStatusBar)
                Toggle(reviewerLocalized("Prefer Hidden Home Indicator"), isOn: $preferences.hideHomeIndicator)
            }
            Section(reviewerLocalized("Toolbar")) {
                Picker(reviewerLocalized("Position"), selection: $preferences.toolbarPosition) {
                    ForEach(ReviewerToolbarPosition.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                NavigationLink(reviewerLocalized("Toolbar Actions")) { ToolbarActionsSettings(preferences: $preferences) }
            }
            Section(reviewerLocalized("Controls")) {
                Picker(reviewerLocalized("Tap Zones"), selection: $preferences.tapZones) {
                    Text("Four Edges", bundle: .module).tag(ReviewerTapZones.edges)
                    Text("Nine Zones", bundle: .module).tag(ReviewerTapZones.grid)
                }
                LabeledContent("Swipe Sensitivity") {
                    Slider(value: decimal(\.swipeSensitivity), in: 50...200, step: 5)
                    Text("\(preferences.swipeSensitivity)%").monospacedDigit()
                }
                Picker(reviewerLocalized("Card Side"), selection: $side) {
                    Text("Question", bundle: .module).tag(ReviewerSide.question)
                    Text("Answer", bundle: .module).tag(ReviewerSide.answer)
                }
                ForEach(preferences.bindings.filter { $0.side == side }) { binding in
                    ReviewerBindingPicker(preferences: $preferences, input: binding.input, side: side)
                }
                Button(reviewerLocalized("Add Binding"), systemImage: "plus") { selectingInput = true }
                Button(reviewerLocalized("Restore Default Bindings")) { preferences.bindings = ReviewerPreferences.defaultBindings }
            }
            #if os(iOS)
            NavigationLink(reviewerLocalized("Text-to-Speech Voices")) { SpeechVoicesScreen() }
            #endif
            Section(reviewerLocalized("Accessibility")) {
                LabeledContent("Card Zoom") {
                    Slider(value: decimal(\.cardZoom), in: 10...300, step: 10)
                    Text("\(preferences.cardZoom)%").monospacedDigit()
                }
                LabeledContent("Image Zoom") {
                    Slider(value: decimal(\.imageZoom), in: 50...300, step: 10)
                    Text("\(preferences.imageZoom)%").monospacedDigit()
                }
                LabeledContent("Answer Button Size") {
                    Slider(value: decimal(\.answerButtonSize), in: 100...200, step: 10)
                    Text("\(preferences.answerButtonSize)%").monospacedDigit()
                }
                Toggle(reviewerLocalized("Reduce Card Animations"), isOn: $preferences.reducedMotion)
                LabeledContent("Minimum Answer Press") {
                    Slider(value: decimal(\.minimumPressMilliseconds), in: 0...2000, step: 10)
                    Text("\(preferences.minimumPressMilliseconds) ms").monospacedDigit()
                }
                LabeledContent("Double Tap Interval") {
                    Slider(value: decimal(\.doubleTapMilliseconds), in: 0...1000, step: 10)
                    Text("\(preferences.doubleTapMilliseconds) ms").monospacedDigit()
                }
            }
        }
        .hayakiScrollBackground()
        .navigationTitle(reviewerLocalized("Reviewer"))
        .onChange(of: preferences) { _, value in value.save() }
        .sheet(isPresented: $selectingInput) {
            NavigationStack {
                ReviewerNewBinding(preferences: $preferences, side: side)
            }
        }
    }

    private func decimal(_ key: WritableKeyPath<ReviewerPreferences, Int>) -> Binding<Double> {
        Binding(
            get: { Double(preferences[keyPath: key]) },
            set: { preferences[keyPath: key] = Int($0) }
        )
    }
}

private struct ToolbarActionsSettings: View {
    @Binding var preferences: ReviewerPreferences

    var body: some View {
        List {
            ForEach(preferences.toolbarOrder) { action in
                Picker(action.title, selection: Binding(
                    get: { preferences.visibility(of: action) },
                    set: { preferences.toolbarVisibility[action] = $0 }
                )) {
                    ForEach(ReviewerToolbarVisibility.allCases, id: \.self) {
                        Text($0.rawValue.capitalized).tag($0)
                    }
                }
            }
            .onMove { preferences.toolbarOrder.move(fromOffsets: $0, toOffset: $1) }
            Button(reviewerLocalized("Restore Toolbar Defaults")) {
                preferences.toolbarOrder = ReviewerToolbarAction.allCases
                preferences.toolbarVisibility = [:]
            }
        }
        .navigationTitle(reviewerLocalized("Toolbar Actions"))
        #if os(iOS)
        .toolbar { EditButton() }
        #endif
    }
}

private struct SchedulingPreferenceSection: View {
    let store: CollectionStore
    @State private var scheduling: Anki_Config_Preferences.Scheduling?
    @State private var saveTask: Task<Void, Never>?
    @State private var error: String?

    var body: some View {
        Section {
            if let scheduling {
                Picker(selection: Binding(
                    get: { scheduling.rollover },
                    set: { update(\.rollover, value: $0) }
                )) {
                    ForEach(0..<24) { hour in
                        Text("\(hour):00").tag(UInt32(hour))
                    }
                } label: { Text("Start of Next Day", bundle: .module) }

                Stepper(
                    value: Binding(
                        get: { Int(scheduling.learnAheadSecs / 60) },
                        set: { update(\.learnAheadSecs, value: UInt32($0 * 60)) }
                    ),
                    in: 0...999
                ) {
                    LabeledContent {
                        Text((Double(scheduling.learnAheadSecs) / 60).formatted(.number.precision(.fractionLength(0))))
                            .monospacedDigit()
                    } label: {
                        Text("Learn Ahead Limit (Minutes)", bundle: .module)
                    }
                }
            }
        } header: {
            Text("Scheduling", bundle: .module)
        }
        .task {
            do { scheduling = try await store.core.getPreferences().scheduling }
            catch { self.error = error.localizedDescription }
        }
        .alert(Text("Could Not Update Scheduling", bundle: .module), isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) {
            Button(role: .cancel) { error = nil } label: { Text("OK", bundle: .module) }
        } message: {
            Text(verbatim: error ?? "")
        }
    }

    private func update(_ key: WritableKeyPath<Anki_Config_Preferences.Scheduling, UInt32> & Sendable, value: UInt32) {
        scheduling?[keyPath: key] = value
        let previous = saveTask
        saveTask = Task {
            await previous?.value
            do {
                try await store.updateSchedulingPreferences { $0[keyPath: key] = value }
            } catch {
                self.error = error.localizedDescription
                scheduling = try? await store.core.getPreferences().scheduling
            }
        }
    }
}

private struct ReviewerCollectionSettings: View {
    let store: CollectionStore
    @State private var reviewing: Anki_Config_Preferences.Reviewing?
    @AppStorage("hayaki.reviewer.customTimeboxMinutes") private var customTimeboxMinutes = 20
    @State private var saveTask: Task<Void, Never>?
    @State private var saveError: String?

    var body: some View {
        Section(reviewerLocalized("Collection")) {
            if let reviewing {
                Toggle(reviewerLocalized("Show Remaining Counts"), isOn: preference(\.showRemainingDueCounts, reviewing))
                Toggle(reviewerLocalized("Show Next Review on Buttons"), isOn: preference(\.showIntervalsOnButtons, reviewing))
                Toggle(reviewerLocalized("Show Card Audio Play Buttons"), isOn: Binding(
                    get: { self.reviewing?.hideAudioPlayButtons == false },
                    set: { update(\.hideAudioPlayButtons, to: !$0) }
                ))
                Toggle(reviewerLocalized("Interrupt Audio When Answering"), isOn: preference(\.interruptAudioWhenAnswering, reviewing))
                let minutes = Int(reviewing.timeLimitSecs) / 60
                Toggle(isOn: Binding(
                    get: { reviewing.timeLimitSecs > 0 },
                    set: { enabled in
                        if !enabled, minutes > 0 { customTimeboxMinutes = minutes }
                        update(\.timeLimitSecs, to: enabled ? UInt32(customTimeboxMinutes * 60) : 0)
                    }
                )) {
                    Text("Use Timebox", bundle: .module)
                }
                if reviewing.timeLimitSecs > 0 {
                    Stepper(value: Binding(
                        get: { max(1, minutes) },
                        set: { newValue in
                            customTimeboxMinutes = newValue
                            update(\.timeLimitSecs, to: UInt32(newValue * 60))
                        }
                    ), in: 1...9999) {
                        LabeledContent {
                            Text(max(1, minutes), format: .number).monospacedDigit()
                        } label: { Text("Timebox (Minutes)", bundle: .module) }
                    }
                }
            }
        }
        .task {
            reviewing = try? await store.core.getPreferences().reviewing
        }
        .alert("Could Not Save Reviewer Setting", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: saveError ?? "")
        }
    }

    private func preference(_ field: WritableKeyPath<Anki_Config_Preferences.Reviewing, Bool>,
                            _ baseline: Anki_Config_Preferences.Reviewing) -> Binding<Bool> {
        Binding(
            get: { (reviewing ?? baseline)[keyPath: field] },
            set: { update(field, to: $0) }
        )
    }

    private func update<Value>(_ field: WritableKeyPath<Anki_Config_Preferences.Reviewing, Value>, to value: Value) {
        reviewing?[keyPath: field] = value
        let previous = saveTask
        saveTask = Task { @MainActor in
            await previous?.value
            do {
                var latest = try await store.core.getPreferences().reviewing
                latest[keyPath: field] = value
                try await store.modify(.setPreferences(.with { $0.reviewing = latest }))
            } catch {
                saveError = error.localizedDescription
                reviewing = try? await store.core.getPreferences().reviewing
            }
        }
    }
}

private struct ReviewerNewBinding: View {
    @Binding var preferences: ReviewerPreferences
    let side: ReviewerSide
    @State private var keyName = ""
    @State private var modifiers: Set<ReviewerKey.Modifier> = []
    @FocusState private var capturingKey: Bool
    @Environment(\.dismiss) private var dismiss

    private static let controllerButtons = [
        "buttonA", "buttonB", "buttonX", "buttonY", "dpadUp", "dpadDown", "dpadLeft", "dpadRight",
        "leftShoulder", "rightShoulder", "leftTrigger", "rightTrigger", "leftStick", "rightStick",
        "buttonMenu", "buttonOptions", "buttonHome",
    ]

    var body: some View {
        Form {
            Section("Keyboard") {
                Button(capturingKey ? "Press a Key" : "Capture Key") { capturingKey = true }
                    .focusable()
                    .focused($capturingKey)
                    .onKeyPress { press in
                        guard capturingKey else { return .ignored }
                        let key = ReviewerKey(press)
                        keyName = key.name
                        modifiers = key.modifiers
                        capturingKey = false
                        return .handled
                    }
                TextField("Key Name", text: $keyName)
                ForEach([ReviewerKey.Modifier.command, .control, .option, .shift], id: \.self) { modifier in
                    Toggle(modifier.rawValue.capitalized, isOn: Binding(
                        get: { modifiers.contains(modifier) },
                        set: { enabled in
                            if enabled { modifiers.insert(modifier) } else { modifiers.remove(modifier) }
                        }
                    ))
                }
                if !keyName.isEmpty {
                    ReviewerBindingPicker(
                        preferences: $preferences, input: .key(keyName, modifiers: modifiers), side: side
                    )
                }
            }
            Section("Gestures") {
                ForEach(preferences.tapZones.gestures + ReviewerGesture.allCases.filter { !$0.isTapZone }, id: \.self) {
                    ReviewerBindingPicker(preferences: $preferences, input: .gesture($0), side: side)
                }
            }
            Section("Controller") {
                ForEach(Self.controllerButtons, id: \.self) {
                    ReviewerBindingPicker(preferences: $preferences, input: .controller($0), side: side)
                }
            }
        }
        .navigationTitle(reviewerLocalized("Add Binding"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

private struct ReviewerBindingPicker: View {
    @Binding var preferences: ReviewerPreferences
    let input: ReviewerInput
    let side: ReviewerSide

    var body: some View {
        Picker(input.title, selection: Binding(
            get: { preferences.command(for: input, on: side) },
            set: { preferences.bind($0, to: input, on: side) }
        )) {
            Text("Unassigned").tag(ReviewerCommand?.none)
            ForEach(ReviewerCommand.allCases, id: \.self) { command in
                Text(command.title).tag(Optional(command))
            }
        }
    }
}

extension ReviewerKey {
    init(_ press: KeyPress) {
        let name: String = switch press.key {
        case .return: "return"
        case .space: "space"
        case .escape: "escape"
        case .upArrow: "arrowup"
        case .downArrow: "arrowdown"
        case .leftArrow: "arrowleft"
        case .rightArrow: "arrowright"
        case .pageUp: "pageup"
        case .pageDown: "pagedown"
        case .tab: "tab"
        case .delete: "backspace"
        default: press.characters
        }
        let mappings: [(EventModifiers, Modifier)] = [
            (.shift, .shift), (.control, .control), (.option, .option), (.command, .command),
        ]
        self.init(name, modifiers: Set(mappings.compactMap { press.modifiers.contains($0.0) ? $0.1 : nil }))
    }
}

extension ReviewerInput {
    var title: String {
        switch self {
        case .gesture(let gesture): gesture.rawValue.reviewerTitle
        case .controller(let button): button.reviewerTitle
        case .keyboard(let key):
            (key.modifiers.map(\.rawValue).sorted().map(\.capitalized) + [key.name.capitalized]).joined(separator: " + ")
        }
    }
}

extension ReviewerCommand {
    var title: String { rawValue.reviewerTitle }
}

private extension String {
    var reviewerTitle: String {
        replacing(/([a-z])([A-Z0-9])/) { "\($0.output.1) \($0.output.2)" }.capitalized
    }
}
