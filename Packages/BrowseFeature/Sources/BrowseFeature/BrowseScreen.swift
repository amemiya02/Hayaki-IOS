import CollectionStore
import SwiftUI

/// How the Browse section appears in the tab bar and sidebar.
public enum BrowseSection {
    public static var title: Text { Text("Browse", bundle: .module) }
    public static let systemImage = "magnifyingglass"
}

/// The Browse section. A placeholder until the card browser is built.
public struct BrowseScreen: View {
    private let store: CollectionStore

    public init(store: CollectionStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label {
                    Text("Browse Is Coming", bundle: .module)
                } icon: {
                    Image(systemName: BrowseSection.systemImage)
                }
            } description: {
                Text("Searching and editing your cards will appear here.", bundle: .module)
            }
            .navigationTitle(BrowseSection.title)
        }
    }
}
