import SwiftUI

enum ReviewerToolbarPosition: String, Codable, CaseIterable {
    case top, bottom, hidden
}

enum ReviewerToolbarVisibility: String, Codable, CaseIterable {
    case toolbar, menu, hidden
}

enum ReviewerToolbarAction: String, Identifiable, CaseIterable, Codable {
    case undo, redo, flag, mark, edit, bury, suspend, deleteNote, toggleWhiteboard
    case browse, statistics, deckOptions, cardInfo, previousCardInfo, addNote, editTags
    case setDueDate, resetProgress, toggleAutoAdvance, recordVoice, replayMedia
    case userAction1, userAction2, userAction3, userAction4, userAction5
    case userAction6, userAction7, userAction8, userAction9

    var id: Self { self }

    var defaultVisibility: ReviewerToolbarVisibility {
        switch self {
        case .undo: .toolbar
        case .browse, .statistics, .toggleAutoAdvance, .recordVoice,
             .userAction1, .userAction2, .userAction3, .userAction4, .userAction5,
             .userAction6, .userAction7, .userAction8, .userAction9: .hidden
        default: .menu
        }
    }

    var command: ReviewerCommand? { ReviewerCommand(rawValue: rawValue) }

    var title: String {
        let key: String
        switch self {
        case .flag: key = "Flag"
        case .bury: key = "Bury"
        case .suspend: key = "Suspend"
        case .mark: key = "Mark Note"
        case .edit: key = "Edit Note"
        case .toggleWhiteboard: key = "Whiteboard"
        case .toggleAutoAdvance: key = "Auto Advance"
        default: return command?.title ?? rawValue
        }
        return reviewerLocalized(key)
    }

    var icon: String {
        switch self {
        case .undo: "arrow.uturn.backward"
        case .redo: "arrow.uturn.forward"
        case .flag: "flag"
        case .mark: "star"
        case .edit: "square.and.pencil"
        case .bury: "rectangle.on.rectangle"
        case .suspend: "pause.circle"
        case .deleteNote: "trash"
        case .toggleWhiteboard: "pencil.tip"
        case .browse: "magnifyingglass"
        case .statistics: "chart.bar"
        case .deckOptions: "slider.horizontal.3"
        case .cardInfo: "info.circle"
        case .previousCardInfo: "clock.arrow.circlepath"
        case .addNote: "plus"
        case .editTags: "tag"
        case .setDueDate: "calendar"
        case .resetProgress: "arrow.counterclockwise"
        case .toggleAutoAdvance: "forward.fill"
        case .recordVoice: "mic"
        case .replayMedia: "play.circle"
        default: "\(command?.userActionNumber ?? 1).circle"
        }
    }
}

struct ReviewerToolbar: View {
    let model: StudySessionModel
    let preferences: ReviewerPreferences
    let showsEditNote: Bool
    let onSettings: () -> Void
    let dispatch: (ReviewerCommand) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(actions(in: .toolbar)) { action in
                        item(action)
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 40, minHeight: 44)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: actions(in: .toolbar).count <= 1, vertical: false)
            Menu {
                ForEach(actions(in: .menu)) { action in item(action) }
                Button(reviewerLocalized("Reviewer Settings"), systemImage: "gear", action: onSettings)
            } label: {
                let flag = StudyFlag(rawValue: model.state.card?.flag ?? 0) ?? .clear
                Image(systemName: flag == .clear ? "ellipsis.circle" : "flag.fill")
                    .foregroundStyle(flag.color)
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Study Actions", bundle: .module))
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
    }

    private func actions(in visibility: ReviewerToolbarVisibility) -> [ReviewerToolbarAction] {
        preferences.toolbarOrder.filter {
            preferences.visibility(of: $0) == visibility && isAvailable($0)
        }
    }

    private func isAvailable(_ action: ReviewerToolbarAction) -> Bool {
        switch action {
        case .undo: model.canUndo
        case .redo: model.canRedo
        case .edit: showsEditNote && model.state.card != nil
        case .browse, .statistics, .deckOptions, .addNote: true
        case .previousCardInfo: model.previousCardID != nil
        default: model.state.card != nil
        }
    }

    @ViewBuilder
    private func item(_ action: ReviewerToolbarAction) -> some View {
        switch action {
        case .flag:
            Menu {
                ForEach(StudyFlag.allCases, id: \.rawValue) { flag in
                    Button { dispatch(flag.command) } label: {
                        Label {
                            flag.title
                        } icon: {
                            Image(systemName: flag.rawValue == model.state.card?.flag ? "checkmark" : "flag")
                        }
                    }
                }
            } label: { Label(action.title, systemImage: action.icon) }
        case .bury:
            Menu {
                commandButton(.buryCard, title: "Bury Card")
                commandButton(.buryNote, title: "Bury Note")
            } label: { Label(action.title, systemImage: action.icon) }
        case .suspend:
            Menu {
                commandButton(.suspendCard, title: "Suspend Card")
                commandButton(.suspendNote, title: "Suspend Note")
            } label: { Label(action.title, systemImage: action.icon) }
        default:
            if let command = action.command {
                let isMarked = action == .mark && model.isCurrentNoteMarked
                Button(role: action == .deleteNote ? .destructive : nil) { dispatch(command) } label: {
                    Label(isMarked ? reviewerLocalized("Unmark Note") : action.title, systemImage: isMarked ? "star.fill" : action.icon)
                }
            }
        }
    }

    private func commandButton(_ command: ReviewerCommand, title: LocalizedStringKey) -> some View {
        Button { dispatch(command) } label: { Text(title, bundle: .module) }
    }
}

enum StudyFlag: UInt32, CaseIterable {
    case clear, red, orange, green, blue, pink, turquoise, purple

    var command: ReviewerCommand {
        switch self {
        case .clear: .clearFlag
        case .red: .flagRed
        case .orange: .flagOrange
        case .green: .flagGreen
        case .blue: .flagBlue
        case .pink: .flagPink
        case .turquoise: .flagTurquoise
        case .purple: .flagPurple
        }
    }

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
