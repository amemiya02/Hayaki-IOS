import AnkiCore
import DeckOptionsFeature
import PackagesFeature
import StudyFeature
import SwiftUI

extension View {
    /// Lets the learner organise the decks of `model`: a toolbar button to
    /// create a deck, and the sheets and alerts behind each deck row's
    /// actions (see `deckActions(for:)`).
    func deckManagement(_ model: DeckListModel, onStudy: @escaping (StudyDeck) -> Void) -> some View {
        modifier(DeckManagement(model: model, onStudy: onStudy))
    }
}

private struct DeckManagement: ViewModifier {
    let model: DeckListModel
    let onStudy: (StudyDeck) -> Void
    @State private var studyAfterDismiss: StudyDeck?
    @State private var request = DeckActionRequest()
    @State private var renaming: DeckNode?
    @State private var newName = ""
    @State private var deleting: (deck: DeckNode, deletion: DeckDeletion)?
    @State private var failure: Failure?

    struct Failure {
        let title: Text
        let message: String
    }

    func body(content: Content) -> some View {
        content
            .environment(request)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NewDeckButton()
                        .environment(request)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        request.pending = .filteredOptions(nil)
                    } label: {
                        Label {
                            Text("New Filtered Deck", bundle: .module)
                        } icon: {
                            Image(systemName: "line.3.horizontal.decrease")
                        }
                    }
                }
            }
            .sheet(item: sheet, onDismiss: startPendingStudy) { action in
                switch action {
                case .create(let parentID):
                    NewDeckSheet(model: model, parentID: parentID) { error in
                        failure = Failure(title: Text("Could Not Create Deck", bundle: .module), message: error.message)
                    }
                case .move(let deck):
                    MoveDeckSheet(model: model, deck: deck) { error in
                        failure = Failure(title: Text("Could Not Move Deck", bundle: .module), message: error.message)
                    }
                case .options(let deck):
                    DeckOptionsScreen(store: model.store, deckID: deck.id)
                case .filteredOptions(let id):
                    FilteredDeckScreen(store: model.store, deckID: id)
                case .customStudy(let deck):
                    CustomStudyScreen(store: model.store, deckID: deck.id) { studyAfterDismiss = $0 }
                case .export(let deck):
                    PackageExportScreen(store: model.store, decks: [deck.id])
                case .rename, .delete, .rebuild, .empty:
                    EmptyView()
                }
            }
            .onChange(of: request.pending) { _, action in
                switch action {
                case .rename(let deck):
                    request.pending = nil
                    newName = deck.name
                    renaming = deck
                case .delete(let deck):
                    request.pending = nil
                    confirmDeletion(of: deck)
                case .rebuild(let deck):
                    request.pending = nil
                    manageFilteredDeck(deck, empty: false)
                case .empty(let deck):
                    request.pending = nil
                    manageFilteredDeck(deck, empty: true)
                case .create, .move, .options, .filteredOptions, .customStudy, .export, nil:
                    break
                }
            }
            .alert(
                Text("Rename Deck", bundle: .module),
                isPresented: isPresented($renaming),
                presenting: renaming
            ) { deck in
                TextField(text: $newName) {
                    Text("Name", bundle: .module)
                }
                Button {
                    rename(deck)
                } label: {
                    Text("Rename", bundle: .module)
                }
                Button(role: .cancel) {} label: {
                    Text("Cancel", bundle: .module)
                }
            }
            .alert(
                Text("Delete “\(deleting?.deck.name ?? "")”?", bundle: .module),
                isPresented: Binding { deleting != nil } set: { if !$0 { deleting = nil } },
                presenting: deleting
            ) { pending in
                Button(role: .destructive) {
                    delete(pending.deck)
                } label: {
                    Text("Delete", bundle: .module)
                }
                Button(role: .cancel) {} label: {
                    Text("Cancel", bundle: .module)
                }
            } message: { pending in
                Self.statement(of: pending.deletion)
            }
            .alert(
                failure?.title ?? Text(verbatim: ""),
                isPresented: isPresented($failure),
                presenting: failure
            ) { _ in
                Button(role: .cancel) {} label: {
                    Text("OK", bundle: .module)
                }
            } message: { failure in
                Text(failure.message)
            }
    }

    /// The pending action when it is shown as a sheet.
    private var sheet: Binding<DeckAction?> {
        Binding {
            switch request.pending {
            case .create, .move, .options, .filteredOptions, .customStudy, .export: request.pending
            default: nil
            }
        } set: { request.pending = $0 }
    }

    private func startPendingStudy() {
        guard let deck = studyAfterDismiss else { return }
        studyAfterDismiss = nil
        onStudy(deck)
    }

    private func isPresented<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
        Binding { value.wrappedValue != nil } set: { if !$0 { value.wrappedValue = nil } }
    }

    /// What deleting a deck takes with it, as the confirmation states it.
    private static func statement(of deletion: DeckDeletion) -> Text {
        if deletion.isFiltered {
            Text("Its cards go back to their original decks.", bundle: .module)
        } else if deletion.subdeckCount == 0 {
            Text("\(deletion.cardCount) cards will be deleted with it.", bundle: .module)
        } else {
            Text(
                "Its \(deletion.subdeckCount) subdecks and \(deletion.cardCount) cards will be deleted with it.",
                bundle: .module
            )
        }
    }

    // MARK: Actions

    private func manageFilteredDeck(_ deck: DeckNode, empty: Bool) {
        let editor = FilteredDeckModel(store: model.store, deckID: deck.id)
        Task {
            if empty {
                await editor.empty()
            } else {
                await editor.rebuild()
            }
            if let error = editor.error {
                failure = Failure(title: Text("Could Not Update Filtered Deck", bundle: .module), message: error)
            }
        }
    }

    /// Counts what goes with the deck, then asks the learner to confirm.
    private func confirmDeletion(of deck: DeckNode) {
        Task {
            do throws(CoreError) {
                deleting = (deck, try await model.deletion(of: deck.id))
            } catch {
                failure = Failure(title: Text("Could Not Delete Deck", bundle: .module), message: error.message)
            }
        }
    }

    private func rename(_ deck: DeckNode) {
        let name = newName
        Task {
            do throws(CoreError) {
                try await model.renameDeck(deck.id, to: name)
            } catch {
                failure = Failure(title: Text("Could Not Rename Deck", bundle: .module), message: error.message)
            }
        }
    }

    private func delete(_ deck: DeckNode) {
        Task {
            do throws(CoreError) {
                try await model.deleteDeck(deck.id)
            } catch {
                failure = Failure(title: Text("Could Not Delete Deck", bundle: .module), message: error.message)
            }
        }
    }
}

struct NewDeckButton: View {
    @Environment(DeckActionRequest.self) private var request: DeckActionRequest

    var body: some View {
        Button {
            request.pending = .create(inside: nil)
        } label: {
            Label {
                Text("New Deck", bundle: .module)
            } icon: {
                Image(systemName: "rectangle.stack.badge.plus")
            }
        }
    }
}
