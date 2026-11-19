import AnkiCore
import AnkiProto
import CollectionStore
import ExtensionBridge
import Foundation
import NoteEditorFeature
import Observation
import SwiftUI
import WidgetKit

/// The app is the only process that uses the Anki core.
@MainActor
@Observable
final class AppExtensions {
    struct EditorDraft: Identifiable {
        let draft: SharedNote
        let editor: NoteEditorModel
        var id: UUID { draft.id }
    }

    var editorDraft: EditorDraft?
    private(set) var isConsuming = false
    @ObservationIgnored private let bridge: ExtensionBridge

    init(bridge: ExtensionBridge) { self.bridge = bridge }

    func keepSnapshotCurrent(store: CollectionStore, profile: CollectionProfile, isCurrent: @escaping () -> Bool) async {
        let changes = store.changes()
        await publish(store: store, profile: profile, isCurrent: isCurrent)
        var refresh: Task<Void, Never>?
        defer { refresh?.cancel() }
        for await event in changes where !event.isDisjoint(with: [.deck, .card, .notetype, .note, .config, .deckConfig, .studyQueues]) {
            refresh?.cancel()
            refresh = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await publish(store: store, profile: profile, isCurrent: isCurrent)
            }
        }
    }

    func publish(store: CollectionStore, profile: CollectionProfile, isCurrent: @escaping () -> Bool) async {
        guard isCurrent(), store.allowsNewProfileWork else { return }
        let previous = bridge.snapshot()
        guard let snapshot = try? await readSnapshot(store: store, profile: profile),
              isCurrent(), store.allowsNewProfileWork, !Task.isCancelled, snapshot != previous
        else { return }

        if (try? bridge.publish(snapshot)) != nil {
            reloadWidgets()
        }
    }

    func clearSnapshot() {
        try? bridge.clearSnapshot()
        reloadWidgets()
    }

    private func reloadWidgets() {
        #if os(iOS)
        WidgetCenter.shared.reloadTimelines(ofKind: ExtensionBridge.deckListWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: ExtensionBridge.singleDeckWidgetKind)
        #endif
    }

    private func readSnapshot(store: CollectionStore, profile: CollectionProfile) async throws -> ExtensionSnapshot {
        let root = try await store.core.deckTree(.with { $0.now = Int64(Date.now.timeIntervalSince1970) })
        let normalDecks = try await store.core.getDeckNames(.with {
            $0.skipEmptyDefault = false
            $0.includeFiltered = false
        })
        var decks = Self.deckRows(root.children)
        // The tree can hide an empty Default deck that people may still add to.
        let ids = Set(decks.map(\.id))
        decks.append(contentsOf: normalDecks.entries.filter { !ids.contains($0.id) }.map {
            ExtensionDeck(id: $0.id, name: $0.name, isFiltered: false, new: 0, learning: 0, review: 0)
        })
        let defaults = try await store.core.defaultsForAdding(.init())
        let names = try await store.core.getNotetypeNames()
        var noteTypes: [ExtensionNoteType] = []
        for name in names.entries {
            let type = try await store.core.getNotetype(.with { $0.ntid = name.id })
            if type.config.originalStockKind != .imageOcclusion, !type.fields.isEmpty {
                noteTypes.append(ExtensionNoteType(id: type.id, name: type.name, fields: type.fields.map(\.name)))
            }
        }
        return ExtensionSnapshot(
            profileID: profile.id, profileName: profile.name, decks: decks, noteTypes: noteTypes,
            defaultDeckID: defaults.deckID, defaultNoteTypeID: defaults.notetypeID
        )
    }

    private static func deckRows(_ nodes: [Anki_Decks_DeckTreeNode], parent: String? = nil) -> [ExtensionDeck] {
        nodes.flatMap { deck in
            let name = parent.map { "\($0)::\(deck.name)" } ?? deck.name
            let row = ExtensionDeck(id: deck.deckID, name: name, isFiltered: deck.filtered,
                                    new: Int(deck.newCount), learning: Int(deck.learnCount), review: Int(deck.reviewCount))
            return [row] + deckRows(deck.children, parent: name)
        }
    }

    /// Quick Add uses the same validation and collection operation as Add Note.
    /// If the destination changed or needs confirmation, hand the text to the editor.
    func consumeNotes(profileID: UUID, store: CollectionStore) async {
        guard !isConsuming, editorDraft == nil, store.allowsNewProfileWork else { return }
        guard let pending = try? bridge.pendingNotes(for: profileID), !pending.isEmpty else { return }
        isConsuming = true
        defer { isConsuming = false }

        for var draft in pending {
            guard store.allowsNewProfileWork, !Task.isCancelled else { return }
            let editor = NoteEditorModel(store: store)
            await editor.load()
            guard editor.state == .ready, !Task.isCancelled else { return }
            let deckExists = editor.decks.contains { $0.id == draft.deckID }
            let typeExists = editor.notetypes.contains { $0.id == draft.noteTypeID }
            if deckExists { editor.selectDeck(draft.deckID) }
            if typeExists { await editor.selectNotetype(draft.noteTypeID) }
            guard editor.state == .ready, !Task.isCancelled else { return }
            let fieldsMatch = editor.fields.map(\.name) == draft.fieldNames && editor.fields.count == draft.values.count
            if fieldsMatch {
                for (index, value) in draft.values.enumerated() { editor.setText(value, ofField: index) }
            } else {
                // Preserve the shared text even if a sync or import changed the field layout.
                editor.setText(draft.values.filter { !$0.isEmpty }.joined(separator: "\n\n"), ofField: 0)
            }

            if draft.mode == .quickAdd && deckExists && typeExists && fieldsMatch {
                // If the app stops after calling the core, review the draft before retrying.
                draft.mode = .fullEditor
                guard (try? bridge.enqueue(draft)) != nil else { return }
                if case .added = await editor.add() {
                    try? bridge.remove(draft)
                    continue
                }
            }
            editorDraft = EditorDraft(draft: draft, editor: editor)
            return
        }
    }

    func dismissDraft(_ draft: EditorDraft) {
        try? bridge.remove(draft.draft)
        editorDraft = nil
    }
}

struct ExtensionIntegration: ViewModifier {
    let store: CollectionStore
    let profile: CollectionProfile
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task(id: profile) {
                await model.appExtensions?.keepSnapshotCurrent(store: store, profile: profile, isCurrent: isCurrent)
            }
            .task(id: scenePhase) {
                guard scenePhase == .active, isCurrent() else { return }
                await model.appExtensions?.publish(store: store, profile: profile, isCurrent: isCurrent)
                await consume()
            }
            .onChange(of: model.collectionIsIdle) { _, ready in
                if ready && scenePhase == .active { Task { await consume() } }
            }
            .onChange(of: model.waitingDeckLink) { _, link in
                if link == nil && scenePhase == .active { Task { await consume() } }
            }
            .sheet(item: Binding(
                get: { model.appExtensions?.editorDraft },
                set: { next in
                    guard next == nil, let service = model.appExtensions, let draft = service.editorDraft else { return }
                    service.dismissDraft(draft)
                }
            ), onDismiss: {
                if scenePhase == .active { Task { await consume() } }
            }) { draft in
                NoteEditorScreen(sharedDraft: draft.editor)
            }
    }

    private func isCurrent() -> Bool { model.activeProfile == profile && model.store === store }

    private func consume() async {
        guard isCurrent(), model.canHandleExtensionWork, model.waitingDeckLink == nil else { return }
        await model.appExtensions?.consumeNotes(profileID: profile.id, store: store)
    }
}
