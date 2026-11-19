import AnkiCore
import AnkiProto
import CollectionStore
import HayakiAppearance
import NoteEditorFeature
import StudyFeature
import SwiftUI

struct GeneralSettingsScreen: View {
    let store: CollectionStore
    @State private var editing: Anki_Config_Preferences.Editing?
    @State private var isSaving = false
    @AppStorage(AppearanceSettings.browseMediaFilenamesKey) private var showsMediaFilenames = false
    @State private var error: String?

    var body: some View {
        Form {
            if let editing {
                Section {
                    Picker(selection: Binding(
                        get: { editing.addingDefaultsToCurrentDeck },
                        set: { update(.addingDefaultsToCurrentDeck, value: $0) }
                    )) {
                        Text("Use Current Deck", bundle: .module).tag(true)
                        Text("Decide by Note Type", bundle: .module).tag(false)
                    } label: { Text("Deck for New Cards", bundle: .module) }
                    Toggle(isOn: Binding(
                        get: { editing.pasteImagesAsPng },
                        set: { update(.pasteImagesAsPng, value: $0) }
                    )) {
                        Text("Paste Clipboard Images as PNG", bundle: .module)
                    }
                } header: {
                    Text("Editing", bundle: .module)
                }
                .disabled(isSaving)
            } else if error == nil {
                ProgressView()
            }
            Section {
                Toggle(isOn: $showsMediaFilenames) {
                    Text("Show Media Filenames in Browse", bundle: .module)
                }
            }
        }
        .hayakiScrollBackground()
        .navigationTitle(Text("General", bundle: .module))
        .task { await load() }
        .alert(Text("Could Not Update Preferences", bundle: .module), isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) {
            Button(role: .cancel) { error = nil } label: { Text("OK", bundle: .module) }
        } message: {
            Text(verbatim: error ?? "")
        }
    }

    private func load() async {
        do { editing = try await store.core.getPreferences().editing }
        catch { self.error = error.localizedDescription }
    }

    private func update(_ key: Anki_Config_ConfigKey.BoolEnum, value: Bool) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await store.modify(.setConfigBool(.with {
                    $0.key = key
                    $0.value = value
                    $0.undoable = true
                }))
                await load()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct AccessibilitySettingsScreen: View {
    let store: CollectionStore
    @AppStorage(AppearanceSettings.browseTextScaleKey) private var browseTextScale = 1.0

    var body: some View {
        Form {
            Section {
                Slider(value: $browseTextScale, in: 0.1...2, step: 0.1) {
                    Text("Browse Text Size", bundle: .module)
                }
                .accessibilityValue(Text(browseTextScale, format: .percent.precision(.fractionLength(0))))
                LabeledContent {
                    Text(browseTextScale, format: .percent.precision(.fractionLength(0)))
                } label: {
                    Text("Browse Text Size", bundle: .module)
                }
                .accessibilityHidden(true)
            }
            Section {
                NavigationLink {
                    ReviewerSettingsScreen(store: store)
                } label: {
                    Text("Reviewer", bundle: .module)
                }
            } footer: {
                Text("Card zoom, image zoom, button size, press duration and card animations are in Reviewer settings.", bundle: .module)
            }
        }
        .hayakiScrollBackground()
        .navigationTitle(Text("Accessibility", bundle: .module))
    }
}

struct AdvancedSettingsScreen: View {
    @AppStorage(StudyDisplayPreferences.focusTypedAnswerKey) private var focusTypedAnswer = true
    @AppStorage(NoteEditorPreferences.replaceNewlinesKey) private var replaceNewlines = true

    var body: some View {
        Form {
            Toggle(isOn: $replaceNewlines) {
                Text("Replace Newlines with HTML", bundle: .module)
            }
            Toggle(isOn: $focusTypedAnswer) {
                Text("Focus Typed Answer", bundle: .module)
            }
        }
        .hayakiScrollBackground()
        .navigationTitle(Text("Advanced", bundle: .module))
    }
}

#if DEBUG
struct DeveloperSettingsScreen: View {
    @AppStorage(StudyDisplayPreferences.inspectCardContentKey) private var inspectCardContent = false

    var body: some View {
        Form {
            Toggle(isOn: $inspectCardContent) {
                Text("Inspect Card Web Views", bundle: .module)
            }
        }
        .hayakiScrollBackground()
        .navigationTitle(Text("Developer Options", bundle: .module))
    }
}
#endif
