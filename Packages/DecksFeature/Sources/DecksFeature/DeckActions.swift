import SwiftUI

/// Something the learner asked to do to organise their decks, waiting for
/// its sheet or alert.
enum DeckAction: Identifiable, Equatable {
    /// Create a deck, at the top level or inside the given deck.
    case create(inside: DeckNode.ID?)
    case rename(DeckNode)
    case move(DeckNode)
    case delete(DeckNode)

    var id: String {
        switch self {
        case .create(let parent): "create-\(parent.map(String.init) ?? "top")"
        case .rename(let deck): "rename-\(deck.id)"
        case .move(let deck): "move-\(deck.id)"
        case .delete(let deck): "delete-\(deck.id)"
        }
    }
}

/// Carries a deck action from a row's menu to the deck list, which presents
/// its sheet or alert.
@MainActor
@Observable
final class DeckActionRequest {
    var pending: DeckAction?
}

/// The deck-organising commands for a deck's context menu: new deck inside,
/// rename, move and delete.
struct DeckActionMenuItems: View {
    let deck: DeckNode
    @Environment(DeckActionRequest.self) private var request: DeckActionRequest?

    var body: some View {
        if !deck.isFiltered {
            Button {
                request?.pending = .create(inside: deck.id)
            } label: {
                Label {
                    Text("New Deck Inside", bundle: .module)
                } icon: {
                    Image(systemName: "rectangle.stack.badge.plus")
                }
            }
        }
        Button {
            request?.pending = .rename(deck)
        } label: {
            Label {
                Text("Rename", bundle: .module)
            } icon: {
                Image(systemName: "pencil")
            }
        }
        Button {
            request?.pending = .move(deck)
        } label: {
            Label {
                Text("Move", bundle: .module)
            } icon: {
                Image(systemName: "folder")
            }
        }
        Divider()
        Button(role: .destructive) {
            request?.pending = .delete(deck)
        } label: {
            Label {
                Text("Delete", bundle: .module)
            } icon: {
                Image(systemName: "trash")
            }
        }
    }
}

extension View {
    /// Adds the deck-organising commands to a deck row: its context menu, and
    /// swipe actions to rename and delete.
    func deckActions(for deck: DeckNode) -> some View {
        modifier(DeckRowActions(deck: deck))
    }
}

private struct DeckRowActions: ViewModifier {
    let deck: DeckNode
    @Environment(DeckActionRequest.self) private var request: DeckActionRequest?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                DeckActionMenuItems(deck: deck)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                // Not a destructive role: the row stays until the learner
                // confirms the deletion.
                Button {
                    request?.pending = .delete(deck)
                } label: {
                    Label {
                        Text("Delete", bundle: .module)
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
                .tint(.red)
                Button {
                    request?.pending = .rename(deck)
                } label: {
                    Label {
                        Text("Rename", bundle: .module)
                    } icon: {
                        Image(systemName: "pencil")
                    }
                }
            }
    }
}
