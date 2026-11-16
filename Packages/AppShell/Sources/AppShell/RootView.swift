import CollectionStore
import PackagesFeature
import SwiftUI

/// The whole app: a short opening state while the collection opens, then the
/// sections.
public struct RootView: View {
    @State private var model = AppModel()

    public init() {}

    public var body: some View {
        Group {
            switch model.state {
            case .opening:
                ProgressView {
                    Text("Opening Your Collection…", bundle: .module)
                }
            case .ready(let store):
                if let packageImport = model.packageImport {
                    SectionsView(store: store)
                        .packageImport(packageImport)
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label {
                        Text("Could Not Open Your Collection", bundle: .module)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                } description: {
                    Text(message)
                }
            }
        }
        .task { await model.open() }
        // A collection package or deck package opened from Files, AirDrop or
        // another app's share sheet.
        .onOpenURL { url in
            Task { await model.openPackage(url) }
        }
    }
}
