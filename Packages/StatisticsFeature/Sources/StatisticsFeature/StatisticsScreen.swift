import CollectionStore
import SwiftUI

/// How the Statistics section appears in the tab bar and sidebar.
public enum StatisticsSection {
    public static var title: Text { Text("Statistics", bundle: .module) }
    public static let systemImage = "chart.bar"
}

/// The Statistics section. A placeholder until the charts are built.
public struct StatisticsScreen: View {
    private let store: CollectionStore

    public init(store: CollectionStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label {
                    Text("Statistics Are Coming", bundle: .module)
                } icon: {
                    Image(systemName: StatisticsSection.systemImage)
                }
            } description: {
                Text("Charts of your studying will appear here.", bundle: .module)
            }
            .navigationTitle(StatisticsSection.title)
        }
    }
}
