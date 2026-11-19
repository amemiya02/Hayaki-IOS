import SwiftUI

/// The actions on the selected cards, in one menu beside Done while the
/// learner selects cards: flag, move, suspend, unsuspend, delete. (A bottom
/// bar would sit under the app's Add Note button.)
struct BulkActionMenu: View {
    let model: CardBrowserModel
    @Binding var isMoving: Bool
    @Binding var deletion: DeletionSummary?
    @Binding var prompt: BrowserActionPrompt?
    let onEdit: () -> Void
    let onInfo: () -> Void
    let onPreview: () -> Void
    let onExport: (Bool) -> Void
    let onChangeNoteType: () -> Void

    var body: some View {
        Menu {
            Menu {
                ForEach(CardRow.Flag.allCases, id: \.self) { flag in
                    Button {
                        perform(.flag(flag))
                    } label: {
                        Label {
                            flag.name
                        } icon: {
                            Image(systemName: "flag.fill")
                        }
                    }
                }
                Divider()
                Button {
                    perform(.flag(nil))
                } label: {
                    Label {
                        Text("No Flag", bundle: .module)
                    } icon: {
                        Image(systemName: "flag.slash")
                    }
                }
            } label: {
                Label {
                    Text("Flag", bundle: .module)
                } icon: {
                    Image(systemName: "flag")
                }
            }
            Button {
                isMoving = true
            } label: {
                Label {
                    Text("Move to Deck…", bundle: .module)
                } icon: {
                    Image(systemName: "folder")
                }
            }
            Button { prompt = .tags } label: {
                Label { Text("Edit Tags", bundle: .module) } icon: { Image(systemName: "tag") }
            }
            Button { perform(.toggleSuspend) } label: {
                Label { Text("Toggle Suspend", bundle: .module) } icon: { Image(systemName: "pause.circle") }
            }
            Divider()
            Button(action: onEdit) {
                Label { Text("Edit Note", bundle: .module) } icon: { Image(systemName: "square.and.pencil") }
            }
            .disabled(model.selection.count != 1)
            Button(action: onPreview) {
                Label { Text("Preview", bundle: .module) } icon: { Image(systemName: "eye") }
            }
            Button(action: onInfo) {
                Label { Text("Card Info", bundle: .module) } icon: { Image(systemName: "info.circle") }
            }
            Button { perform(.toggleMark) } label: {
                Label { Text("Toggle Mark", bundle: .module) } icon: { Image(systemName: "star") }
            }
            Button(action: onChangeNoteType) {
                Label { Text("Change Note Type…", bundle: .module) } icon: { Image(systemName: "arrow.left.arrow.right") }
            }
            Button { prompt = .replace } label: {
                Label { Text("Find and Replace", bundle: .module) } icon: { Image(systemName: "text.magnifyingglass") }
            }
            Menu {
                Button { onExport(true) } label: { Text("Deck Package", bundle: .module) }
                Button { onExport(false) } label: { Text("Text File", bundle: .module) }
            } label: {
                Label { Text("Export Selection", bundle: .module) } icon: { Image(systemName: "square.and.arrow.up") }
            }
            Divider()
            Button { prompt = .dueDate } label: { BrowserActionPrompt.dueDate.title }
            Button { prompt = .reposition } label: { BrowserActionPrompt.reposition.title }
            Button { prompt = .grade } label: { BrowserActionPrompt.grade.title }
            Button { prompt = .reset } label: { BrowserActionPrompt.reset.title }
            Button { perform(.toggleBury) } label: {
                Label { Text("Toggle Bury", bundle: .module) } icon: { Image(systemName: "moon.zzz") }
            }
            Divider()
            Button(role: .destructive) {
                Task { deletion = await model.deletionSummary() }
            } label: {
                Label {
                    Text("Delete…", bundle: .module)
                } icon: {
                    Image(systemName: "trash")
                }
            }
        } label: {
            Label {
                Text("Actions", bundle: .module)
            } icon: {
                Image(systemName: "ellipsis")
            }
        }
    }

    private func perform(_ action: BulkAction) {
        Task { await model.perform(action) }
    }
}

/// Lets the learner pick the deck to move the selected cards to.
struct MoveCardsSheet: View {
    let model: CardBrowserModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.choices.moveDestinations) { deck in
                Button {
                    dismiss()
                    Task { await model.perform(.move(toDeck: deck.id)) }
                } label: {
                    let parts = deck.name.components(separatedBy: "::")
                    Text(verbatim: parts.last ?? deck.name)
                        .padding(.leading, CGFloat(parts.count - 1) * 20)
                        // Indentation is not spoken: name the decks it sits
                        // in too.
                        .accessibilityLabel(Text(verbatim: parts.joined(separator: ", ")))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle(model.mode == .cards
                ? Text("Move \(model.selection.count) Cards", bundle: .module)
                : Text("Move \(model.selection.count) Notes", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Text("Cancel", bundle: .module)
                    }
                }
            }
        }
    }
}

/// The message after a bulk action, with a button that undoes it.
struct UndoBanner: View {
    let model: CardBrowserModel
    let completed: CompletedAction

    var body: some View {
        HStack(spacing: 12) {
            message
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await model.undoLastAction() }
            } label: {
                Text("Undo", bundle: .module)
                    .bold()
            }
            .keyboardShortcut("z", modifiers: .command)
            Button {
                model.dismissCompletedAction()
            } label: {
                Label {
                    Text("Dismiss", bundle: .module)
                } icon: {
                    Image(systemName: "xmark")
                }
                .labelStyle(.iconOnly)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var message: Text {
        let count = completed.cardCount
        return switch completed.action {
        case .suspend: Text("Suspended \(count) cards", bundle: .module)
        case .unsuspend: Text("Unsuspended \(count) cards", bundle: .module)
        case .flag(nil): Text("Removed the flag from \(count) cards", bundle: .module)
        case .flag: Text("Flagged \(count) cards", bundle: .module)
        case .move: Text("Moved \(count) cards", bundle: .module)
        case .delete: Text("Deleted \(count) cards", bundle: .module)
        default: Text(verbatim: completed.undoName)
        }
    }
}
