import AnkiCore
import SwiftUI

struct ReviewerTagsSheet: View {
    let model: StudySessionModel
    let noteID: Int64
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String?
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                if draft != nil {
                    TextField(reviewerLocalized("Tags"), text: Binding(get: { draft ?? "" }, set: { draft = $0 }))
                        .autocorrectionDisabled()
                    Text("Separate tags with spaces.", bundle: .module)
                        .foregroundStyle(.secondary)
                } else if error == nil {
                    ProgressView()
                }
            }
            .navigationTitle(reviewerLocalized("Edit Tags"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(reviewerLocalized("Cancel"), role: .cancel) { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(reviewerLocalized("Save"), action: save).disabled(draft == nil || isSaving)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .task {
            do {
                draft = try await model.tags(of: noteID).joined(separator: " ")
            } catch {
                self.error = (error as? CoreError)?.message ?? error.localizedDescription
            }
        }
        .alert(reviewerLocalized("Could Not Edit Tags"), isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button(reviewerLocalized("OK"), role: .cancel) { if draft == nil { dismiss() } }
        } message: {
            Text(verbatim: error ?? "")
        }
    }

    private func save() {
        guard let draft else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await model.setTags(draft.split(whereSeparator: \.isWhitespace).map(String.init), on: noteID)
                dismiss()
            } catch {
                self.error = (error as? CoreError)?.message ?? error.localizedDescription
            }
        }
    }
}
