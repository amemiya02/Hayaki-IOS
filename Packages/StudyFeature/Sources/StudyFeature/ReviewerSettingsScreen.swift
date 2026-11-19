import SwiftUI

/// Settings shared by the reviewer and the app's More screen.
public struct ReviewerSettingsScreen: View {
    @State private var preferences = ReviewerPreferences.load()
    @State private var side: ReviewerSide = .question
    @State private var selectingInput = false

    public init() {}

    public var body: some View {
        Form {
            Section("Controls") {
                Picker("Tap Zones", selection: $preferences.tapZones) {
                    Text("Four Edges").tag(ReviewerTapZones.edges)
                    Text("Nine Zones").tag(ReviewerTapZones.grid)
                }
                LabeledContent("Swipe Sensitivity") {
                    Slider(value: decimal(\.swipeSensitivity), in: 50...200, step: 5)
                    Text("\(preferences.swipeSensitivity)%").monospacedDigit()
                }
                Picker("Card Side", selection: $side) {
                    Text("Question").tag(ReviewerSide.question)
                    Text("Answer").tag(ReviewerSide.answer)
                }
                ForEach(preferences.bindings.filter { $0.side == side }) { binding in
                    ReviewerBindingPicker(preferences: $preferences, input: binding.input, side: side)
                }
                Button("Add Binding", systemImage: "plus") { selectingInput = true }
                Button("Restore Default Bindings") { preferences.bindings = ReviewerPreferences.defaultBindings }
            }
            #if os(iOS)
            NavigationLink("Text-to-Speech Voices") { SpeechVoicesScreen() }
            #endif
            Section("Accessibility") {
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
        .navigationTitle("Reviewer")
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
        .navigationTitle("Add Binding")
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
