import AnkiCore
import AnkiProto
import CollectionStore
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
            if let store { ReviewerCollectionSettings(store: store) }
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
                    ForEach(ReviewerToolbarPosition.allCases, id: \.self) { Text(reviewerLocalized($0.rawValue.capitalized)).tag($0) }
                }
                NavigationLink(reviewerLocalized("Toolbar Actions")) { ToolbarActionsSettings(preferences: $preferences) }
            }
            Section(reviewerLocalized("Controls")) {
                Picker(reviewerLocalized("Tap Zones"), selection: $preferences.tapZones) {
                    Text("Four Edges", bundle: .module).tag(ReviewerTapZones.edges)
                    Text("Nine Zones", bundle: .module).tag(ReviewerTapZones.grid)
                }
                LabeledContent(reviewerLocalized("Swipe Sensitivity")) {
                    Slider(value: decimal(\.swipeSensitivity), in: 50...200, step: 5)
                    Text(Double(preferences.swipeSensitivity) / 100, format: .percent).monospacedDigit()
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
                LabeledContent(reviewerLocalized("Card Zoom")) {
                    Slider(value: decimal(\.cardZoom), in: 10...300, step: 10)
                    Text(Double(preferences.cardZoom) / 100, format: .percent).monospacedDigit()
                }
                LabeledContent(reviewerLocalized("Image Zoom")) {
                    Slider(value: decimal(\.imageZoom), in: 50...300, step: 10)
                    Text(Double(preferences.imageZoom) / 100, format: .percent).monospacedDigit()
                }
                LabeledContent(reviewerLocalized("Answer Button Size")) {
                    Slider(value: decimal(\.answerButtonSize), in: 100...200, step: 10)
                    Text(Double(preferences.answerButtonSize) / 100, format: .percent).monospacedDigit()
                }
                Toggle(reviewerLocalized("Reduce Card Animations"), isOn: $preferences.reducedMotion)
                LabeledContent(reviewerLocalized("Minimum Answer Press")) {
                    Slider(value: decimal(\.minimumPressMilliseconds), in: 0...2000, step: 10)
                    Text("\(preferences.minimumPressMilliseconds) ms", bundle: .module).monospacedDigit()
                }
                LabeledContent(reviewerLocalized("Double Tap Interval")) {
                    Slider(value: decimal(\.doubleTapMilliseconds), in: 0...1000, step: 10)
                    Text("\(preferences.doubleTapMilliseconds) ms", bundle: .module).monospacedDigit()
                }
            }
        }
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
                        Text(reviewerLocalized($0.rawValue.capitalized)).tag($0)
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

private struct ReviewerCollectionSettings: View {
    let store: CollectionStore
    @State private var reviewing: Anki_Config_Preferences.Reviewing?
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
                Stepper(
                    value: Binding(
                        get: { Int(self.reviewing?.timeLimitSecs ?? 0) / 60 },
                        set: { update(\.timeLimitSecs, to: UInt32($0 * 60)) }
                    ), in: 0...240
                ) {
                    if minutes == 0 {
                        Text("Timebox Off", bundle: .module)
                    } else {
                        Text("Timebox: \(minutes) min", bundle: .module)
                    }
                }
            }
        }
        .task {
            reviewing = try? await store.core.getPreferences().reviewing
        }
        .alert(reviewerLocalized("Could Not Save Reviewer Setting"), isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button(reviewerLocalized("OK"), role: .cancel) {}
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
                var config = try await store.core.getPreferences()
                config.reviewing[keyPath: field] = value
                try await store.modify(.setPreferences(config))
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
            Section(reviewerLocalized("Keyboard")) {
                Button(reviewerLocalized(capturingKey ? "Press a Key" : "Capture Key")) { capturingKey = true }
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
                TextField(reviewerLocalized("Key Name"), text: $keyName)
                ForEach([ReviewerKey.Modifier.command, .control, .option, .shift], id: \.self) { modifier in
                    Toggle(reviewerLocalized(modifier.rawValue.capitalized), isOn: Binding(
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
            Section(reviewerLocalized("Gestures")) {
                ForEach(preferences.tapZones.gestures + ReviewerGesture.allCases.filter { !$0.isTapZone }, id: \.self) {
                    ReviewerBindingPicker(preferences: $preferences, input: .gesture($0), side: side)
                }
            }
            Section(reviewerLocalized("Controller")) {
                ForEach(Self.controllerButtons, id: \.self) {
                    ReviewerBindingPicker(preferences: $preferences, input: .controller($0), side: side)
                }
            }
        }
        .navigationTitle(reviewerLocalized("Add Binding"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(reviewerLocalized("Done")) { dismiss() } } }
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
            Text("Unassigned", bundle: .module).tag(ReviewerCommand?.none)
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
        case .gesture(let gesture): reviewerLocalized(gesture.rawValue.reviewerTitle)
        case .controller(let button): reviewerLocalized(button.reviewerTitle)
        case .keyboard(let key):
            (key.modifiers.map(\.rawValue).sorted().map { reviewerLocalized($0.capitalized) }
                + [reviewerLocalized(key.name.capitalized)]).joined(separator: " + ")
        }
    }
}

extension ReviewerCommand {
    var title: String {
        if let number = userActionNumber {
            return String(localized: "User Action \(number)", bundle: .module)
        }
        return reviewerLocalized(rawValue.reviewerTitle)
    }
}

private extension String {
    var reviewerTitle: String {
        replacing(/([a-z])([A-Z0-9])/) { "\($0.output.1) \($0.output.2)" }.capitalized
    }
}
