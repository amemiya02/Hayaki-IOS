import SwiftUI

struct ProfilesScreen: View {
    let model: AppModel
    @State private var editor: NameEditor?
    @State private var switchTarget: CollectionProfile?
    @State private var switchError: String?
    @State private var deleteTarget: CollectionProfile?
    @State private var deleteError: String?

    var body: some View {
        List(model.profiles) { profile in
            let isActive = profile.id == model.activeProfile.id
            HStack {
                Button {
                    if !isActive { switchTarget = profile }
                } label: {
                    HStack {
                        Text(verbatim: profile.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if isActive {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isActive ? .isSelected : [])

                Button {
                    editor = .rename(profile)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Rename \(profile.name)", bundle: .module))
            }
            .swipeActions {
                if !isActive && model.profiles.count > 1 {
                    Button {
                        deleteTarget = profile
                    } label: {
                        Label {
                            Text("Delete Profile", bundle: .module)
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                    .tint(.red)
                }
            }
        }
        .navigationTitle(Text("Profiles", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button {
                    editor = .add
                } label: {
                    Label {
                        Text("Add Profile", bundle: .module)
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
                .accessibilityIdentifier("add-profile")
            }
        }
        .sheet(item: $editor) { editor in
            ProfileNameSheet(editor: editor, model: model)
                .presentationDetents([.medium, .large])
        }
        .alert(
            Text("Switch Profile?", bundle: .module),
            isPresented: Binding(get: { switchTarget != nil }, set: { if !$0 { switchTarget = nil } }),
            presenting: switchTarget
        ) { profile in
            Button {
                Task {
                    do {
                        try await model.switchProfile(to: profile.id)
                    } catch {
                        switchError = error.localizedDescription
                    }
                }
            } label: {
                Text("Switch Profile", bundle: .module)
            }
            Button(role: .cancel) { switchTarget = nil } label: {
                Text("Cancel", bundle: .module)
            }
        } message: { profile in
            Text("Close your current collection and open “\(profile.name)”?", bundle: .module)
        }
        .alert(
            Text("Could Not Switch Profiles", bundle: .module),
            isPresented: Binding(get: { switchError != nil }, set: { if !$0 { switchError = nil } })
        ) {
            Button { switchError = nil } label: { Text("OK", bundle: .module) }
        } message: {
            Text(verbatim: switchError ?? "")
        }
        .alert(
            Text("Delete Profile?", bundle: .module),
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            presenting: deleteTarget
        ) { profile in
            Button(role: .destructive) {
                Task {
                    do {
                        try await model.deleteProfile(profile.id)
                    } catch {
                        deleteError = error.localizedDescription
                    }
                }
            } label: {
                Text("Delete Profile", bundle: .module)
            }
            Button(role: .cancel) { deleteTarget = nil } label: {
                Text("Cancel", bundle: .module)
            }
        } message: { profile in
            Text("Permanently delete the collection, media, backups and sign-in for “\(profile.name)” from this device?",
                 bundle: .module)
        }
        .alert(
            Text("Could Not Finish Deleting Profile", bundle: .module),
            isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
        ) {
            Button { deleteError = nil } label: { Text("OK", bundle: .module) }
        } message: {
            Text(verbatim: deleteError ?? "")
        }
    }
}

private enum NameEditor: Identifiable {
    case add
    case rename(CollectionProfile)

    var id: String {
        switch self {
        case .add: "new"
        case .rename(let profile): profile.id.uuidString
        }
    }

    var title: Text {
        switch self {
        case .add: Text("Add Profile", bundle: .module)
        case .rename: Text("Rename Profile", bundle: .module)
        }
    }

    var initialName: String {
        switch self {
        case .add: ""
        case .rename(let profile): profile.name
        }
    }
}

private struct ProfileNameSheet: View {
    let editor: NameEditor
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditingName: Bool
    @State private var name: String
    @State private var errorMessage: String?

    init(editor: NameEditor, model: AppModel) {
        self.editor = editor
        self.model = model
        _name = State(initialValue: editor.initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $name) { Text("Profile Name", bundle: .module) }
                    .focused($isEditingName)
                    .onSubmit(save)
                    .onChange(of: name) { errorMessage = nil }
                    .accessibilityIdentifier("profile-name")
                if let errorMessage {
                    Text(verbatim: errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(editor.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Text("Save", bundle: .module) }
                }
            }
        }
        .task { isEditingName = true }
    }

    private func save() {
        do {
            switch editor {
            case .add:
                try model.addProfile(named: name)
            case .rename(let profile):
                try model.renameProfile(profile.id, to: name)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
