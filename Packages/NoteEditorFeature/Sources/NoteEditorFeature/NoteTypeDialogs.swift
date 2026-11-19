import AnkiCore
import SwiftUI

struct NoteTypeTextEdit: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let label: LocalizedStringKey
    let initial: String
    var allowsEmpty = false
    let submit: (String) async throws -> Void
}

struct NoteTypeTextSheet: View {
    let edit: NoteTypeTextEdit
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var value: String
    @State private var busy = false
    @State private var failure: String?

    init(edit: NoteTypeTextEdit) {
        self.edit = edit
        _value = State(initialValue: edit.initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $value) { Text(edit.label, bundle: .module) }
                    .focused($isFocused)
                    .onSubmit { Task { await save() } }
                if edit.allowsEmpty {
                    Text("Use a language tag such as ja-JP. Leave it blank to clear the preference.", bundle: .module)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(busy)
            .navigationTitle(Text(edit.title, bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }.disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: { Text("Save", bundle: .module) }
                        .disabled(busy || (!edit.allowsEmpty && trimmedValue.isEmpty))
                }
            }
            .noteTypeError($failure)
        }
        .interactiveDismissDisabled(busy)
        .presentationDetents([.medium])
        .task { isFocused = true }
    }

    private var trimmedValue: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        guard !busy, edit.allowsEmpty || !trimmedValue.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            try await edit.submit(trimmedValue)
            dismiss()
        } catch { failure = error.localizedDescription }
    }
}

extension View {
    func noteTypeError(_ message: Binding<String?>) -> some View {
        alert(
            Text("Could Not Complete the Action", bundle: .module),
            isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } }),
            presenting: message.wrappedValue
        ) { _ in
            Button(role: .cancel) {} label: { Text("OK", bundle: .module) }
        } message: { message in
            Text(message)
        }
    }

    func noteTypeSyncConfirmation(
        isPresented: Binding<Bool>,
        onCancel: @escaping () -> Void = {},
        onConfirm: @escaping () -> Void
    ) -> some View {
        alert(Text("One-Way Sync Required", bundle: .module), isPresented: isPresented) {
            Button(action: onConfirm) { Text("Continue", bundle: .module) }
            Button(role: .cancel, action: onCancel) { Text("Cancel", bundle: .module) }
        } message: {
            Text("Your next sync will need to upload or download the entire collection.", bundle: .module)
        }
    }
}
