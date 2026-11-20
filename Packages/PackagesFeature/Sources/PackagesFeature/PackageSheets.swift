import CollectionStore
import SwiftUI

/// A sheet that a package button opens.
public enum PackageSheet: Hashable, Identifiable, Sendable {
    case exportPackage
    case exportText
    case sharedDecks

    public var id: Self { self }
}

/// Opens one of the package sheets. Set by `packageSheets(store:)`.
public struct ShowPackageSheetAction: Sendable {
    let action: @MainActor @Sendable (PackageSheet) -> Void

    @MainActor
    public func callAsFunction(_ sheet: PackageSheet) { action(sheet) }
}

extension EnvironmentValues {
    @Entry public var showPackageSheet: ShowPackageSheetAction?
}

extension View {
    /// Presents the sheets of `ExportPackageButton`, `TextExportButton` and
    /// `SharedDecksLink` from this view instead of from the buttons. Use it
    /// when those buttons sit in a `Menu`: a menu's items go away when it
    /// closes, and a sheet attached to them would never show.
    public func packageSheets(store: CollectionStore) -> some View {
        modifier(PackageSheetsModifier(store: store))
    }
}

private struct PackageSheetsModifier: ViewModifier {
    let store: CollectionStore
    @Environment(\.importPackage) private var importPackage
    @State private var sheet: PackageSheet?
    @State private var importAfterDismiss = false

    func body(content: Content) -> some View {
        content
            .environment(\.showPackageSheet, ShowPackageSheetAction { sheet = $0 })
            .sheet(item: $sheet, onDismiss: openDownloadedPackage) { sheet in
                switch sheet {
                case .exportPackage:
                    PackageExportScreen(store: store)
                case .exportText:
                    TextExportScreen(store: store)
                case .sharedDecks:
                    SharedDecksCatalog {
                        importAfterDismiss = true
                        self.sheet = nil
                    } onDone: {
                        self.sheet = nil
                    }
                }
            }
    }

    private func openDownloadedPackage() {
        guard importAfterDismiss else { return }
        importAfterDismiss = false
        importPackage?()
    }
}
