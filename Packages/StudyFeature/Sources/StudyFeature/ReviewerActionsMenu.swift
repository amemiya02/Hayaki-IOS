import SwiftUI

/// Actions that apply to the current review, card or note.
struct ReviewerActionsMenu: View {
    let model: StudySessionModel
    let showsEditNote: Bool
    let onEditNote: (Int64) -> Void
    @State private var editingDueDate = false
    @State private var confirmingReset = false
    @State private var confirmingDelete = false
    @State private var dueDays = ""

    var body: some View {
        Menu {
            if model.canUndo {
                Button { Task { await model.undo() } } label: {
                    Label {
                        Text("Undo", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                }
            }
            if model.canRedo {
                Button { Task { await model.redo() } } label: {
                    Label {
                        Text("Redo", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                }
            }
            if let card = model.state.card {
                Section {
                    if showsEditNote {
                        Button { onEditNote(card.id) } label: {
                            Label {
                                Text("Edit Note", bundle: .module)
                            } icon: {
                                Image(systemName: "square.and.pencil")
                            }
                        }
                    }
                    if card.isNoteMarked {
                        option("Unmark Note") { await model.toggleMark() }
                    } else {
                        option("Mark Note") { await model.toggleMark() }
                    }
                    Menu {
                        option("Bury Card") { await model.bury(note: false) }
                        option("Bury Note") { await model.bury(note: true) }
                    } label: {
                        Text("Bury", bundle: .module)
                    }
                    Menu {
                        option("Suspend Card") { await model.suspend(note: false) }
                        option("Suspend Note") { await model.suspend(note: true) }
                    } label: {
                        Text("Suspend", bundle: .module)
                    }
                    Menu {
                        ForEach(StudyFlag.allCases, id: \.rawValue) { flag in
                            Button {
                                Task { await model.setFlag(flag.rawValue) }
                            } label: {
                                Label {
                                    flag.title
                                } icon: {
                                    Image(systemName: flag.rawValue == card.flag ? "checkmark" : "flag")
                                }
                            }
                        }
                    } label: {
                        Text("Flag", bundle: .module)
                    }
                }
                Section {
                    Button {
                        dueDays = ""
                        editingDueDate = true
                    } label: {
                        Text("Set Due Date", bundle: .module)
                    }
                    Button {
                        confirmingReset = true
                    } label: {
                        Text("Reset Progress", bundle: .module)
                    }
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Text("Delete Note", bundle: .module)
                    }
                }
            }
        } label: {
            Image(systemName: (model.state.card?.flag ?? 0) > 0 ? "flag.fill" : "ellipsis.circle")
                .foregroundStyle(StudyFlag(rawValue: model.state.card?.flag ?? 0)?.color ?? .primary)
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .disabled(model.isBusy)
        .accessibilityLabel(Text("Study Actions", bundle: .module))
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

    private func option(_ title: LocalizedStringKey, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Text(title, bundle: .module)
        }
    }
}

private enum StudyFlag: UInt32, CaseIterable {
    case clear, red, orange, green, blue, pink, turquoise, purple

    var title: Text {
        switch self {
        case .clear: Text("Clear Flag", bundle: .module)
        case .red: Text("Red", bundle: .module)
        case .orange: Text("Orange", bundle: .module)
        case .green: Text("Green", bundle: .module)
        case .blue: Text("Blue", bundle: .module)
        case .pink: Text("Pink", bundle: .module)
        case .turquoise: Text("Turquoise", bundle: .module)
        case .purple: Text("Purple", bundle: .module)
        }
    }

    var color: Color {
        switch self {
        case .clear: .primary
        case .red: .red
        case .orange: .orange
        case .green: .green
        case .blue: .blue
        case .pink: .pink
        case .turquoise: .cyan
        case .purple: .purple
        }
    }
}
