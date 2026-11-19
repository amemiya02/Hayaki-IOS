import SwiftUI

/// Confirmation and due-date entry shared by toolbar and physical commands.
struct ReviewerActionDialogs: ViewModifier {
    let model: StudySessionModel
    @Binding var requestedAction: ReviewerCommand?
    @State private var editingDueDate = false
    @State private var confirmingReset = false
    @State private var confirmingDelete = false
    @State private var dueDays = ""

    func body(content: Content) -> some View {
        content
            .onChange(of: requestedAction) { _, action in
                guard let action else { return }
                switch action {
                case .setDueDate:
                    dueDays = ""
                    editingDueDate = true
                case .resetProgress: confirmingReset = true
                case .deleteNote: confirmingDelete = true
                default: break
                }
            }
            .onChange(of: editingDueDate) { _, shown in
                if !shown { requestedAction = nil }
            }
            .onChange(of: confirmingReset) { _, shown in
                if !shown { requestedAction = nil }
            }
            .onChange(of: confirmingDelete) { _, shown in
                if !shown { requestedAction = nil }
            }
            .alert(Text("Set Due Date", bundle: .module), isPresented: $editingDueDate) {
                TextField(text: $dueDays) { Text("Days", bundle: .module) }
                Button {
                    let entered = dueDays.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !entered.isEmpty else { return }
                    Task { await model.setDueDate(entered) }
                } label: {
                    Text("Save", bundle: .module)
                }
                Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
            } message: {
                Text("Enter the number of days until the card is due. Use 0 for today or a range such as 3-7.", bundle: .module)
            }
            .alert(Text("Reset Progress", bundle: .module), isPresented: $confirmingReset) {
                Button(role: .destructive) {
                    Task { await model.resetProgress() }
                } label: {
                    Text("Reset", bundle: .module)
                }
                Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
            } message: {
                Text("This card will be scheduled as a new card.", bundle: .module)
            }
            .alert(Text("Delete Note", bundle: .module), isPresented: $confirmingDelete) {
                Button(role: .destructive) {
                    Task { await model.deleteNote() }
                } label: {
                    Text("Delete", bundle: .module)
                }
                Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
            } message: {
                Text("Delete this note and all of its cards?", bundle: .module)
            }
    }

}
