import SwiftUI

/// The preset the deck uses, how many decks share it, and commands to add,
/// clone, rename and delete presets.
struct PresetSection: View {
    @Bindable var model: DeckOptionsModel
    @State private var naming: Naming?
    @State private var name = ""
    @State private var confirmingDelete = false

    /// Which command asked for a preset name.
    enum Naming: Identifiable {
        case add, clone, rename
        var id: Self { self }
    }

    var body: some View {
        Section {
            Picker(selection: $model.selectedPresetID) {
                ForEach(model.presets) { preset in
                    Text(verbatim: preset.name).tag(preset.id)
                }
            } label: {
                Text("Preset", bundle: .module)
            }
            Menu {
                Button {
                    ask(.add, suggesting: "")
                } label: {
                    Label { Text("Add Preset", bundle: .module) } icon: { Image(systemName: "plus") }
                }
                Button {
                    ask(.clone, suggesting: String(
                        localized: "\(model.selectedPreset?.name ?? "") copy",
                        bundle: .module,
                        comment: "Suggested name for a copy of a preset. The placeholder is the preset's name."
                    ))
                } label: {
                    Label { Text("Clone Preset", bundle: .module) } icon: { Image(systemName: "plus.square.on.square") }
                }
                Button {
                    ask(.rename, suggesting: model.selectedPreset?.name ?? "")
                } label: {
                    Label { Text("Rename Preset", bundle: .module) } icon: { Image(systemName: "pencil") }
                }
                Divider()
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label { Text("Delete Preset", bundle: .module) } icon: { Image(systemName: "trash") }
                }
                .disabled(!model.canDeleteSelectedPreset)
            } label: {
                Text("Manage Presets", bundle: .module)
            }
        } header: {
            Text("Preset", bundle: .module)
        } footer: {
            sharingNote
        }
        .alert(
            title(of: naming),
            isPresented: Binding { naming != nil } set: { if !$0 { naming = nil } },
            presenting: naming
        ) { naming in
            TextField(text: $name) {
                Text("Name", bundle: .module)
            }
            Button {
                apply(naming)
            } label: {
                naming == .rename ? Text("Rename", bundle: .module) : Text("Add", bundle: .module)
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            Button(role: .cancel) {} label: {
                Text("Cancel", bundle: .module)
            }
        }
        .confirmationDialog(
            Text("Delete “\(model.selectedPreset?.name ?? "")”?", bundle: .module),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                model.deleteSelectedPreset()
            } label: {
                Text("Delete Preset", bundle: .module)
            }
        } message: {
            deletionNote
        }
    }

    /// Whether other decks use the preset too, so that changing it changes
    /// them as well.
    private var sharingNote: Text {
        let count = model.selectedPreset?.deckCount ?? 1
        return count > 1
            ? Text("Used by \(count) decks. Changes apply to all of them.", bundle: .module)
            : Text("Used only by this deck.", bundle: .module)
    }

    private var deletionNote: Text {
        let count = model.selectedPreset?.deckCount ?? 1
        return count > 1
            ? Text("The \(count) decks using it will use the Default preset instead. Takes effect when you save.", bundle: .module)
            : Text("This deck will use the Default preset instead. Takes effect when you save.", bundle: .module)
    }

    private func title(of naming: Naming?) -> Text {
        switch naming {
        case .add, nil: Text("Add Preset", bundle: .module)
        case .clone: Text("Clone Preset", bundle: .module)
        case .rename: Text("Rename Preset", bundle: .module)
        }
    }

    private func ask(_ kind: Naming, suggesting suggestion: String) {
        name = suggestion
        naming = kind
    }

    private func apply(_ kind: Naming) {
        switch kind {
        case .add: model.addPreset(named: name)
        case .clone: model.cloneSelectedPreset(named: name)
        case .rename: model.renameSelectedPreset(to: name)
        }
    }
}
