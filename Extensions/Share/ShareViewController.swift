import ExtensionBridge
import SwiftUI
import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let screen = ShareNoteScreen(
            bridge: ExtensionBridge.appGroup,
            loadText: { [weak self] in try await self?.sharedText() },
            finish: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        )
        let host = UIHostingController(rootView: screen)
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    private func sharedText() async throws -> String? {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        for item in items {
            for provider in item.attachments ?? [] where provider.canLoadObject(ofClass: NSString.self) {
                let text: String? = await withCheckedContinuation { continuation in
                    _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                        continuation.resume(returning: (value as? NSString).map { $0 as String })
                    }
                }
                if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
            }
            if let text = item.attributedContentText?.string, !text.isEmpty { return text }
        }
        return nil
    }
}

private struct ShareNoteScreen: View {
    let bridge: ExtensionBridge?
    let loadText: @MainActor () async throws -> String?
    let finish: @MainActor () -> Void

    @State private var snapshot: ExtensionSnapshot?
    @State private var selectedDeck: Int64?
    @State private var selectedType: Int64?
    @State private var values: [String] = []
    @State private var loaded = false
    @State private var failure = false
    @State private var saved: SharedNote.Mode?

    var body: some View {
        NavigationStack {
            Group {
                if let saved {
                    ContentUnavailableView {
                        Label("Shared Note Queued", systemImage: "checkmark.circle")
                    } description: {
                        if saved == .fullEditor {
                            Text("Open Hayaki to finish editing this note.")
                        } else {
                            Text("Hayaki will add this note the next time you open it.")
                        }
                    } actions: {
                        Button("Done", action: finish)
                    }
                } else if let snapshot, let type = noteType {
                    editor(snapshot, type)
                } else if loaded {
                    ContentUnavailableView {
                        Label("Could Not Add Shared Text", systemImage: "square.and.arrow.down")
                    } description: {
                        Text("Share selected text after opening your collection in Hayaki.")
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Add to Hayaki")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if saved == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel, action: finish) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save(.quickAdd) }.disabled(!canSave)
                    }
                }
            }
        }
        .task {
            defer { loaded = true }
            guard let text = try? await loadText(), let data = bridge?.snapshot(),
                  let type = data.noteTypes.first(where: { $0.id == data.defaultNoteTypeID }) ?? data.noteTypes.first,
                  let deck = data.decks.first(where: { $0.id == data.defaultDeckID && !$0.isFiltered })
                    ?? data.decks.first(where: { !$0.isFiltered })
            else { return }

            snapshot = data
            selectedDeck = deck.id
            selectedType = type.id
            values = type.fields.indices.map { $0 == 0 ? text : "" }
        }
        .alert("Could Not Queue the Note", isPresented: $failure) {
            Button("OK", role: .cancel) {}
        }
    }

    private var noteType: ExtensionNoteType? {
        snapshot?.noteTypes.first { $0.id == selectedType }
    }

    private var canSave: Bool {
        selectedDeck != nil && noteType != nil
            && values.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func editor(_ snapshot: ExtensionSnapshot, _ type: ExtensionNoteType) -> some View {
        Form {
            Section {
                LabeledContent("Profile", value: snapshot.profileName)
                Picker("Deck", selection: $selectedDeck) {
                    ForEach(snapshot.decks.filter { !$0.isFiltered }) { deck in
                        Text(verbatim: deck.name).tag(Optional(deck.id))
                    }
                }
                Picker("Note Type", selection: Binding(
                    get: { selectedType },
                    set: { id in
                        guard let next = snapshot.noteTypes.first(where: { $0.id == id }) else { return }
                        values = next.fields.indices.map { values.indices.contains($0) ? values[$0] : "" }
                        selectedType = id
                    }
                )) {
                    ForEach(snapshot.noteTypes) { option in
                        Text(verbatim: option.name).tag(Optional(option.id))
                    }
                }
            }
            Section {
                ForEach(type.fields.indices, id: \.self) { index in
                    TextField(
                        type.fields[index],
                        text: Binding(
                            get: { values.indices.contains(index) ? values[index] : "" },
                            set: { if values.indices.contains(index) { values[index] = $0 } }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(2...8)
                }
            }
            Button("Continue in Full Editor") { save(.fullEditor) }.disabled(!canSave)
        }
    }

    private func save(_ mode: SharedNote.Mode) {
        guard let bridge, let snapshot, let type = noteType, let selectedDeck, canSave else { return }
        let draft = SharedNote(
            profileID: snapshot.profileID, deckID: selectedDeck, noteTypeID: type.id,
            fieldNames: type.fields, values: values, mode: mode
        )
        do {
            try bridge.enqueue(draft)
            saved = mode
        } catch {
            failure = true
        }
    }
}
