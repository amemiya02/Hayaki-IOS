import SwiftUI
import UniformTypeIdentifiers

// MARK: Starting an import from any screen

/// Shows the file picker for choosing a package to import. Set by
/// `packageImport(_:)`; a screen offers it with `ImportPackageButton`.
public struct ImportPackageAction: Sendable {
    let action: @MainActor @Sendable () -> Void

    @MainActor
    public func callAsFunction() { action() }
}

extension EnvironmentValues {
    @Entry public var importPackage: ImportPackageAction?
}

/// A button that lets the learner choose a collection package or deck package
/// to import. It does nothing outside a view with `packageImport(_:)`.
public struct ImportPackageButton: View {
    @Environment(\.importPackage) private var importPackage

    public init() {}

    public var body: some View {
        Button {
            importPackage?()
        } label: {
            Label {
                Text("Import a Package…", bundle: .module)
            } icon: {
                Image(systemName: "square.and.arrow.down")
            }
        }
        .disabled(importPackage == nil)
    }
}

extension View {
    /// Handles importing packages for everything inside: the file picker
    /// that `ImportPackageButton` opens, the confirmation, merge choices,
    /// progress and summary of `model`'s import.
    public func packageImport(_ model: PackageImportModel) -> some View {
        modifier(PackageImportModifier(model: model))
    }
}

private struct PackageImportModifier: ViewModifier {
    @Bindable var model: PackageImportModel
    @State private var isChoosingFile = false

    func body(content: Content) -> some View {
        content
            .environment(\.importPackage, ImportPackageAction { isChoosingFile = true })
            .fileImporter(
                isPresented: $isChoosingFile,
                allowedContentTypes: [.ankiCollectionPackage, .ankiDeckPackage]
            ) { result in
                switch result {
                case .success(let url):
                    Task { await model.open(url) }
                case .failure:
                    break
                }
            }
            .sheet(isPresented: sheetShown) {
                ImportSheet(model: model)
            }
    }

    /// Every step of an import shows in one sheet. (Switching between a
    /// sheet and alerts as the steps change makes UIKit drop presentations
    /// that start while another is still closing.)
    private var sheetShown: Binding<Bool> {
        Binding {
            model.step != .idle
        } set: { shown in
            if !shown { model.dismiss() }
        }
    }
}

// MARK: The sheet: merge choices, progress, summary

private struct ImportSheet: View {
    @Bindable var model: PackageImportModel

    var body: some View {
        NavigationStack {
            switch model.step {
            case .choosingMergeOptions(let package):
                MergeOptionsForm(model: model, package: package)
            case .importing(let package, let progress):
                ImportProgressView(model: model, package: package, progress: progress)
            case .preparing(let name):
                ImportProgressView(model: model, package: nil, progress: nil, preparing: name)
            case .confirmingReplace(let package):
                ReplaceConfirmation(model: model, package: package)
            case .finished(let summary):
                ImportSummaryView(model: model, summary: summary)
            case .cancelled:
                ImportEnded(model: model, title: Text("Import Cancelled", bundle: .module), message: Text("Your collection was not changed.", bundle: .module))
            case .failed(let message):
                ImportEnded(model: model, title: Text("Could Not Import", bundle: .module), message: Text(message))
            case .idle:
                EmptyView()
            }
        }
        .interactiveDismissDisabled(model.isImporting)
    }
}

/// The warning before a collection package replaces the collection.
private struct ReplaceConfirmation: View {
    let model: PackageImportModel
    let package: PackageFile

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Replace Your Collection?", bundle: .module)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        } description: {
            Text(
                "Everything in Hayaki will be replaced by the collection in “\(package.name)”. A backup of your current collection is made first.",
                bundle: .module
            )
        } actions: {
            Button(role: .destructive) {
                Task { await model.startImport() }
            } label: {
                Text("Replace", bundle: .module)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    model.cancel()
                } label: {
                    Text("Cancel", bundle: .module)
                }
            }
        }
    }
}

/// How an import that did not finish ended: cancelled, or failed and why.
private struct ImportEnded: View {
    let model: PackageImportModel
    let title: Text
    let message: Text

    var body: some View {
        ContentUnavailableView {
            Label {
                title
            } icon: {
                Image(systemName: "xmark.circle")
            }
        } description: {
            message
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    model.dismiss()
                } label: {
                    Text("OK", bundle: .module)
                }
            }
        }
    }
}

private struct MergeOptionsForm: View {
    @Bindable var model: PackageImportModel
    let package: PackageFile

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $model.mergeOptions.includeLearningProgress) {
                    Text("Import Learning Progress", bundle: .module)
                }
                Toggle(isOn: $model.mergeOptions.includeDeckPresets) {
                    Text("Import Deck Presets", bundle: .module)
                }
            } footer: {
                Text(
                    "Learning progress is the scheduling and review history of cards new to your collection. Cards you already have keep their own progress.",
                    bundle: .module
                )
            }
            Section {
                Picker(selection: $model.mergeOptions.updateNotes) {
                    UpdateConditionOptions()
                } label: {
                    Text("Update Notes", bundle: .module)
                }
                Picker(selection: $model.mergeOptions.updateNotetypes) {
                    UpdateConditionOptions()
                } label: {
                    Text("Update Note Types", bundle: .module)
                }
                Toggle(isOn: $model.mergeOptions.mergeNotetypes) {
                    Text("Merge Note Types", bundle: .module)
                }
            } header: {
                Text("Notes Already in Your Collection", bundle: .module)
            } footer: {
                Text(
                    "“If Newer” replaces a note only when the package’s copy was changed more recently. Merging note types combines a changed note type with yours instead of keeping both.",
                    bundle: .module
                )
            }
        }
        .navigationTitle(package.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    model.cancel()
                } label: {
                    Text("Cancel", bundle: .module)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await model.startImport() }
                } label: {
                    Text("Import", bundle: .module)
                }
            }
        }
    }
}

private struct UpdateConditionOptions: View {
    var body: some View {
        Text("If Newer", bundle: .module).tag(MergeOptions.UpdateCondition.ifNewer)
        Text("Always", bundle: .module).tag(MergeOptions.UpdateCondition.always)
        Text("Never", bundle: .module).tag(MergeOptions.UpdateCondition.never)
    }
}

private struct ImportProgressView: View {
    let model: PackageImportModel
    let package: PackageFile?
    let progress: String?
    var preparing: String?

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let progress {
                Text(progress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if package != nil {
                Button(role: .cancel) {
                    model.cancel()
                } label: {
                    Text("Cancel Import", bundle: .module)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        if let package {
            String(localized: "Importing “\(package.name)”…", bundle: .module, comment: "Shown while a package imports; the placeholder is the file name.")
        } else {
            String(localized: "Opening “\(preparing ?? "")”…", bundle: .module, comment: "Shown while the chosen package is copied before importing; the placeholder is the file name.")
        }
    }
}

private struct ImportSummaryView: View {
    let model: PackageImportModel
    let summary: ImportSummary

    var body: some View {
        List {
            switch summary {
            case .replaced(let result):
                Section {
                    LabeledContent {
                        Text(result.decks, format: .number)
                    } label: {
                        Text("Decks", bundle: .module)
                    }
                    LabeledContent {
                        Text(result.notes, format: .number)
                    } label: {
                        Text("Notes", bundle: .module)
                    }
                    LabeledContent {
                        Text(result.cards, format: .number)
                    } label: {
                        Text("Cards", bundle: .module)
                    }
                } header: {
                    Text("Your Collection Now Has", bundle: .module)
                } footer: {
                    if result.backupMade {
                        Text("A backup of your previous collection was saved in the Backups folder.", bundle: .module)
                    }
                }
            case .merged(let result):
                NoteListSection(
                    title: Text("Added", bundle: .module),
                    explanation: Text("Notes new to your collection.", bundle: .module),
                    notes: result.added
                )
                NoteListSection(
                    title: Text("Updated", bundle: .module),
                    explanation: Text("Notes you already had, replaced by the package’s copy.", bundle: .module),
                    notes: result.updated
                )
                NoteListSection(
                    title: Text("Skipped", bundle: .module),
                    explanation: Text("Notes you already had, left as they were. Their cards keep your scheduling.", bundle: .module),
                    notes: result.unchanged
                )
                if !result.conflicting.isEmpty {
                    NoteListSection(
                        title: Text("Skipped: Different Note Type", bundle: .module),
                        explanation: Text("Notes you already had with another note type. Turn on Merge Note Types to update them.", bundle: .module),
                        notes: result.conflicting
                    )
                }
            }
        }
        .navigationTitle(Text("Import Complete", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    model.dismiss()
                } label: {
                    Text("Done", bundle: .module)
                }
            }
        }
    }
}

/// A count of notes that can be expanded to list them.
private struct NoteListSection: View {
    let title: Text
    let explanation: Text
    let notes: [String]

    var body: some View {
        Section {
            if notes.isEmpty {
                LabeledContent {
                    Text(0, format: .number)
                } label: {
                    title
                }
            } else {
                DisclosureGroup {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        Text(note.isEmpty ? "—" : note)
                            .lineLimit(2)
                    }
                } label: {
                    LabeledContent {
                        Text(notes.count, format: .number)
                    } label: {
                        title
                    }
                }
            }
        } footer: {
            explanation
        }
    }
}
