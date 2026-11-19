import BrowseFeature
import CollectionStore
import DeckOptionsFeature
import DecksFeature
import NoteEditorFeature
import StatisticsFeature
import StudyFeature
import SwiftUI

/// Handles reviewer navigation in the app shell where the other features are available.
struct ReviewerDestinationView: View {
    let route: ReviewerDestination
    let store: CollectionStore
    let study: @MainActor (StudyDeck) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch route {
        case .browse(let search):
            closable {
                BrowseScreen(store: store, initialSearch: search)
            }
        case .statistics:
            closable {
                // The statistics screen opens with the core's current deck selected.
                StatisticsScreen(store: store)
            }
        case .deckOptions(let deckID):
            DeckOptionsScreen(store: store, deckID: deckID)
        case .customStudy(let deckID):
            CustomStudyScreen(store: store, deckID: deckID, onStart: study)
        case .cardInfo(let cardID):
            NavigationStack {
                CardInfoScreen(store: store, cardID: cardID)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { close }
                    }
            }
        case .addNote(let homeDeckID):
            NoteEditorScreen(store: store, homeDeckID: homeDeckID)
        }
    }

    private func closable<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                close
            }
            .padding(.horizontal)
            .padding(.top, 4)
            content()
        }
    }

    private var close: some View {
        Button(role: .close) { dismiss() }
            .keyboardShortcut(.cancelAction)
    }
}
