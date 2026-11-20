import CollectionStore
import HayakiAppearance
import SwiftUI

/// A button that opens the export screen for the whole collection.
public struct ExportPackageButton: View {
    private let store: CollectionStore
    @Environment(\.showPackageSheet) private var showPackageSheet
    @State private var isExporting = false

    public init(store: CollectionStore) {
        self.store = store
    }

    public var body: some View {
        Button {
            if let showPackageSheet {
                showPackageSheet(.exportPackage)
            } else {
                isExporting = true
            }
        } label: {
            Label {
                Text("Export…", bundle: .module)
            } icon: {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .sheet(isPresented: $isExporting) {
            PackageExportScreen(store: store)
        }
    }
}

/// Exporting a package, shown as a sheet: what to export and how, the core's
/// progress, and the finished file with a share button.
public struct PackageExportScreen: View {
    @State private var model: PackageExportModel?
    @Environment(\.dismiss) private var dismiss
    private let store: CollectionStore
    private let decks: Set<Int64>
    private let selection: ExportSelection?

    /// - Parameter decks: Decks to start with as a deck package; empty to
    ///   start with the whole collection.
    public init(store: CollectionStore, decks: Set<Int64> = [], selection: ExportSelection? = nil) {
        self.store = store
        self.decks = decks
        self.selection = selection
    }

    public var body: some View {
        NavigationStack {
            if let model {
                ExportContent(model: model) { dismiss() }
            } else {
                ExportEnded(
                    title: Text("Could Not Export", bundle: .module),
                    message: Text("Hayaki cannot reach its Documents folder.", bundle: .module),
                    systemImage: "xmark.circle"
                ) { dismiss() }
            }
        }
        .interactiveDismissDisabled(model?.isExporting ?? false)
        .onAppear {
            guard model == nil, let folder = try? PackageExportModel.standardExportFolder() else { return }
            model = PackageExportModel(store: store, exportFolder: folder, decks: decks, selection: selection)
        }
    }
}

private struct ExportContent: View {
    @Bindable var model: PackageExportModel
    let close: () -> Void

    var body: some View {
        switch model.step {
        case .choosing:
            ExportChoices(model: model, close: close)
        case .exporting(let progress):
            ExportProgressView(model: model, progress: progress)
        case .finished(let package):
            ExportFinished(package: package, close: close)
        case .cancelled:
            ExportEnded(
                title: Text("Export Cancelled", bundle: .module),
                message: Text("No file was saved.", bundle: .module),
                systemImage: "xmark.circle",
                close: close
            )
        case .failed(let message):
            ExportEnded(
                title: Text("Could Not Export", bundle: .module),
                message: Text(message),
                systemImage: "exclamationmark.triangle",
                close: close
            )
        }
    }
}

// MARK: Choices

private struct ExportChoices: View {
    @Bindable var model: PackageExportModel
    let close: () -> Void

    var body: some View {
        Form {
            if model.selection != nil {
                Text("Export Selection as Deck Package", bundle: .module)
            } else {
                Section {
                    Picker(selection: $model.kind) {
                        Text("Collection Package", bundle: .module).tag(PackageKind.collectionPackage)
                        Text("Deck Package", bundle: .module).tag(PackageKind.deckPackage)
                    } label: {
                        Text("Export", bundle: .module)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } footer: {
                    switch model.kind {
                    case .collectionPackage:
                        Text(
                            "Your whole collection, with its scheduling and review history. Importing it into Anki or AnkiDroid replaces the collection there.",
                            bundle: .module
                        )
                    case .deckPackage:
                        Text(
                            "The decks you choose, each with its subdecks. Importing it into Anki or AnkiDroid adds them to the collection there.",
                            bundle: .module
                        )
                    }
                }

                if model.kind == .deckPackage {
                    DeckChoices(model: model)
                }

            }
            Section {
                if model.kind == .deckPackage {
                    Toggle(isOn: $model.options.includeScheduling) {
                        Text("Include Scheduling Information", bundle: .module)
                    }
                    Toggle(isOn: $model.options.includeDeckPresets) {
                        Text("Include Deck Presets", bundle: .module)
                    }
                }
                Toggle(isOn: $model.options.includeMedia) {
                    Text("Include Media", bundle: .module)
                }
                Toggle(isOn: $model.options.supportOlderVersions) {
                    Text("Support Older Anki Versions", bundle: .module)
                }
            } header: {
                Text("Options", bundle: .module)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if model.kind == .deckPackage {
                        Text(
                            "Without scheduling information the cards arrive as new cards, with no review history. Leave it off to share decks; turn it on to move your progress.",
                            bundle: .module
                        )
                    }
                    Text(
                        "Turn on support for older versions only for Anki before 2.1.50 or an old AnkiDroid; the file is larger and slower to make.",
                        bundle: .module
                    )
                }
            }
        }
        .navigationTitle(Text("Export", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    close()
                } label: {
                    Text("Cancel", bundle: .module)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await model.export() }
                } label: {
                    Text("Export", bundle: .module)
                }
                .disabled(!model.canExport)
            }
        }
        .task { await model.loadDecks() }
    }
}

/// The decks to put in a deck package, ticked in a list indented like the
/// deck list.
private struct DeckChoices: View {
    @Bindable var model: PackageExportModel

    var body: some View {
        Section {
            ForEach(model.decks) { deck in
                let isChosen = model.selectedDeckIDs.contains(deck.id)
                Button {
                    if isChosen {
                        model.selectedDeckIDs.remove(deck.id)
                    } else {
                        model.selectedDeckIDs.insert(deck.id)
                    }
                } label: {
                    HStack {
                        Text(deck.name)
                            .foregroundStyle(.primary)
                            .padding(.leading, CGFloat(deck.depth) * 20)
                        Spacer()
                        if isChosen {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                // Deck names in the text colour, as in a list of choices.
                .tint(.primary)
                .accessibilityLabel(Text(deck.fullName.replacingOccurrences(of: "::", with: ", ")))
                .accessibilityAddTraits(isChosen ? .isSelected : [])
            }
        } header: {
            Text("Decks", bundle: .module)
        } footer: {
            if model.decks.isEmpty {
                Text("There are no decks to export.", bundle: .module)
            }
        }
    }
}

// MARK: Progress and result

private struct ExportProgressView: View {
    let model: PackageExportModel
    let progress: String?

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Exporting…", bundle: .module)
                .font(.headline)
            if let progress {
                Text(progress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(role: .cancel) {
                model.cancel()
            } label: {
                Text("Cancel Export", bundle: .module)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

private struct ExportFinished: View {
    let package: ExportedPackage
    let close: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(package.name)
            } icon: {
                Image(systemName: "doc.zipper")
            }
        } description: {
            VStack(spacing: 8) {
                Text(package.byteCount, format: .byteCount(style: .file))
                Text(
                    "Saved in the Exports folder, which you can find under Hayaki in the Files app. Share it to AirDrop it, save it elsewhere or open it in another app.",
                    bundle: .module
                )
            }
        } actions: {
            ShareLink(item: package.url) {
                Label {
                    Text("Share…", bundle: .module)
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .hayakiProminentLabel()
            .controlSize(.large)
        }
        .navigationTitle(Text("Export Complete", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    close()
                } label: {
                    Text("Done", bundle: .module)
                }
            }
        }
    }
}

/// How an export that did not finish ended: cancelled, or failed and why.
private struct ExportEnded: View {
    let title: Text
    let message: Text
    let systemImage: String
    let close: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                title
            } icon: {
                Image(systemName: systemImage)
            }
        } description: {
            message
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    close()
                } label: {
                    Text("OK", bundle: .module)
                }
            }
        }
    }
}
