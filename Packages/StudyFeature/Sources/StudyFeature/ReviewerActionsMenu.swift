import SwiftUI

/// Actions that apply to the current review, card or note.
struct ReviewerActionsMenu: View {
    let model: StudySessionModel

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
