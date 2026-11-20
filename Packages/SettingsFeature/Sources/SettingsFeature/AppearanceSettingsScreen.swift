import HayakiAppearance
import SwiftUI
import UniformTypeIdentifiers

struct AppearanceSettingsScreen: View {
    let background: DeckBackground
    private var settings = AppearanceSettings()
    @AppStorage(DeckBackground.revisionKey) private var backgroundRevision = ""
    @State private var choosingImage = false
    @State private var removingImage = false
    @State private var updatingImage = false
    @State private var backgroundError: String?

    var body: some View {
        Form {
            Section {
                Picker(selection: Binding(get: { settings.mode }, set: { settings.mode = $0 })) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        title(for: mode).tag(mode)
                    }
                } label: { Text("Theme", bundle: .module) }
                .accessibilityIdentifier("appearance-theme")

                Picker(selection: Binding(get: { settings.systemNightMode }, set: { settings.systemNightMode = $0 })) {
                    Text("Dark", bundle: .module).tag(SystemNightMode.dark)
                    Text("Black", bundle: .module).tag(SystemNightMode.black)
                } label: { Text("System Night Theme", bundle: .module) }
                .disabled(settings.mode != .system)
            } footer: {
                Text("System uses Light when the device uses Light Mode and your night theme in Dark Mode.", bundle: .module)
            }

            Section {
                Button {
                    choosingImage = true
                } label: {
                    Label {
                        Text("Choose Background Image", bundle: .module)
                    } icon: { Image(systemName: "photo") }
                }
                Button(role: .destructive) {
                    removingImage = true
                } label: {
                    Text("Remove Background Image", bundle: .module)
                }
                .disabled(!background.exists)
                .id(backgroundRevision)
            } header: {
                Text("Deck List Background", bundle: .module)
            }
            .disabled(updatingImage)
        }
        .hayakiScrollBackground()
        .navigationTitle(Text("Appearance", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .fileImporter(isPresented: $choosingImage, allowedContentTypes: [.image]) { result in
            updatingImage = true
            Task {
                defer { updatingImage = false }
                do {
                    try await background.replace(with: result.get())
                    backgroundRevision = UUID().uuidString
                } catch {
                    backgroundError = error.localizedDescription
                }
            }
        }
        .confirmationDialog(Text("Remove Background Image", bundle: .module), isPresented: $removingImage) {
            Button(role: .destructive) {
                do {
                    try background.remove()
                    backgroundRevision = UUID().uuidString
                } catch {
                    backgroundError = error.localizedDescription
                }
            } label: { Text("Remove Background Image", bundle: .module) }
        }
        .alert(Text("Could Not Update Background", bundle: .module), isPresented: Binding(
            get: { backgroundError != nil }, set: { if !$0 { backgroundError = nil } }
        )) {
            Button(role: .cancel) { backgroundError = nil } label: { Text("OK", bundle: .module) }
        } message: {
            Text(verbatim: backgroundError ?? "")
        }
    }

    private func title(for mode: AppearanceMode) -> Text {
        switch mode {
        case .system: Text("System", bundle: .module)
        case .light: Text("Light", bundle: .module)
        case .dark: Text("Dark", bundle: .module)
        case .black: Text("Black", bundle: .module)
        }
    }
}
