import SwiftUI

/// The Decks sync action and the collection's current sync status.
public struct DeckSyncButton: View {
    private let model: SyncModel
    @State private var showsSync = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: SyncModel) {
        self.model = model
    }

    public var body: some View {
        Button {
            showsSync = true
            guard model.account != nil, model.canStartManualSync else { return }
            Task { await model.sync() }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: model.isTransferring && !reduceMotion)
                .overlay(alignment: .topTrailing) {
                    if let badge = model.badge {
                        Image(systemName: badge == .oneWay ? "exclamationmark.circle.fill" : "circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(badge == .signedOut ? Color.secondary : Color.orange)
                            .background(.background, in: Circle())
                            .offset(x: 4, y: -3)
                            .accessibilityHidden(true)
                    }
                }
        }
        .accessibilityLabel(Text("Sync", bundle: .module))
        .accessibilityValue(badgeDescription)
        .accessibilityIdentifier("deck-sync")
        .sheet(isPresented: $showsSync, onDismiss: model.dismissMeteredConfirmation) {
            NavigationStack {
                SyncScreen(model: model)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                showsSync = false
                            } label: {
                                Text("Done", bundle: .module)
                            }
                        }
                    }
            }
        }
    }

    private var badgeDescription: Text {
        if model.isTransferring { return Text("Syncing…", bundle: .module) }
        return switch model.badge {
        case .signedOut: Text("Signed Out", bundle: .module)
        case .pendingChanges: Text("Changes to Sync", bundle: .module)
        case .oneWay: Text("One-Way Sync Required", bundle: .module)
        case nil: Text(verbatim: "")
        }
    }
}
