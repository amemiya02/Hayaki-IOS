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
        let destinationChanged: Bool
        let sceneID: UUID
        var id: UUID { draft.id }
    }

    private(set) var editorDraft: EditorDraft?
    private(set) var isConsuming = false
    @ObservationIgnored private let bridge: ExtensionBridge
    @ObservationIgnored private var noteTypeCache: (profileID: UUID, types: [ExtensionNoteType])?
    @ObservationIgnored private var noteTypeRevision = 0
    @ObservationIgnored private var startedPublication = 0
    @ObservationIgnored private var completedPublication = 0

    init(bridge: ExtensionBridge) { self.bridge = bridge }

    func keepSnapshotCurrent(store: CollectionStore, profile: CollectionProfile, isCurrent: @escaping () -> Bool) async {
        let changes = store.changes()
        await publish(store: store, profile: profile, isCurrent: isCurrent)
        var refresh: Task<Void, Never>?
        defer { refresh?.cancel() }
        for await event in changes where !event.isDisjoint(with: [.deck, .card, .notetype, .note, .config, .deckConfig, .studyQueues]) {
            if event.contains(.notetype) { invalidateNoteTypes() }
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
        startedPublication += 1
        let publication = startedPublication
        guard let snapshot = try? await readSnapshot(store: store, profile: profile),
              isCurrent(), store.allowsNewProfileWork, !Task.isCancelled, publication > completedPublication
        else { return }

        completedPublication = publication
        if snapshot != bridge.snapshot(), (try? bridge.publish(snapshot)) != nil {
            reloadWidgets()
        }
    }

    func clearSnapshot() {
        invalidateNoteTypes()
        try? bridge.clearSnapshot()
        reloadWidgets()
    }

    private func invalidateNoteTypes() {
        noteTypeRevision += 1
        noteTypeCache = nil
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
            ExtensionDeck(id: $0.id, name: $0.name, isFiltered: false, new: 0, learning: 0, review: 0, isVisibleInWidget: false)
        })
        let defaults = try await store.core.defaultsForAdding(.init())
        let types = try await noteTypes(in: store, profileID: profile.id)
        return ExtensionSnapshot(
            profileID: profile.id, profileName: profile.name, decks: decks, noteTypes: types,
            defaultDeckID: defaults.deckID, defaultNoteTypeID: defaults.notetypeID
        )
    }

    private func noteTypes(in store: CollectionStore, profileID: UUID) async throws -> [ExtensionNoteType] {
        if let noteTypeCache, noteTypeCache.profileID == profileID { return noteTypeCache.types }
        let revision = noteTypeRevision
        let names = try await store.core.getNotetypeNames()
        var noteTypes: [ExtensionNoteType] = []
        for name in names.entries {
            try Task.checkCancellation()
            let type = try await store.core.getNotetype(.with { $0.ntid = name.id })
            if type.config.originalStockKind != .imageOcclusion, !type.fields.isEmpty {
                noteTypes.append(ExtensionNoteType(id: type.id, name: type.name, fields: type.fields.map(\.name)))
            }
        }
        if revision == noteTypeRevision { noteTypeCache = (profileID, noteTypes) }
        return noteTypes
    }

    private static func deckRows(_ nodes: [Anki_Decks_DeckTreeNode], parent: String? = nil) -> [ExtensionDeck] {
        nodes.flatMap { deck in
            let name = parent.map { "\($0)::\(deck.name)" } ?? deck.name
            let row = ExtensionDeck(id: deck.deckID, name: name, isFiltered: deck.filtered,
                                    new: Int(deck.newCount), learning: Int(deck.learnCount), review: Int(deck.reviewCount),
                                    isVisibleInWidget: deck.deckID != 1 || deck.totalIncludingChildren > 0)
            return [row] + deckRows(deck.children, parent: name)
        }
    }

    /// Quick Add uses the same validation and collection operation as Add Note.
    /// If the destination changed or needs confirmation, hand the text to the editor.
    func consumeNotes(profileID: UUID, store: CollectionStore, sceneID: UUID) async {
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
            if typeExists { await editor.selectNotetype(draft.noteTypeID) }
            guard editor.state == .ready, !Task.isCancelled else { return }
            if deckExists { editor.selectDeck(draft.deckID) }
            let fieldsMatch = editor.fields.map(\.name) == draft.fieldNames && editor.fields.count == draft.values.count
            if fieldsMatch {
                for (index, value) in draft.values.enumerated() { editor.setText(value, ofField: index) }
            } else {
                // Preserve the shared text even if a sync or import changed the field layout.
                editor.setText(draft.values.filter { !$0.isEmpty }.joined(separator: "\n\n"), ofField: 0)
            }

            let destinationChanged = !deckExists || !typeExists || !fieldsMatch
            if draft.mode == .quickAdd && !destinationChanged {
                // If the app stops after calling the core, review the draft before retrying.
                draft.mode = .fullEditor
                guard (try? bridge.enqueue(draft)) != nil else { return }
                if case .added = await editor.add() {
                    try? bridge.remove(draft)
                    continue
                }
            }
            editorDraft = EditorDraft(
                draft: draft, editor: editor, destinationChanged: destinationChanged, sceneID: sceneID
            )
            return
        }
    }

    func dismissDraft(_ draft: EditorDraft) {
        guard editorDraft?.id == draft.id else { return }
        try? bridge.remove(draft.draft)
        editorDraft = nil
    }

    func releaseDraft(in sceneID: UUID) {
        if editorDraft?.sceneID == sceneID { editorDraft = nil }
    }
}

struct ExtensionIntegration: ViewModifier {
    let store: CollectionStore
    let profile: CollectionProfile
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var sceneID = UUID()

    func body(content: Content) -> some View {
        content
            .task(id: profile) {
                await model.appExtensions?.keepSnapshotCurrent(store: store, profile: profile, isCurrent: isCurrent)
            }
            .task(id: scenePhase) {
                guard (scenePhase == .active || scenePhase == .background), isCurrent() else { return }
                await model.appExtensions?.publish(store: store, profile: profile, isCurrent: isCurrent)
                if scenePhase == .active { await consume() }
            }
            .onChange(of: model.collectionIsIdle) { _, ready in
                if ready && scenePhase == .active { Task { await consume() } }
            }
            .onChange(of: model.waitingDeckLink) { _, link in
                if link == nil && scenePhase == .active { Task { await consume() } }
            }
            .onDisappear {
                model.appExtensions?.releaseDraft(in: sceneID)
            }
            .sheet(item: Binding(
                get: {
                    guard let draft = model.appExtensions?.editorDraft, draft.sceneID == sceneID else { return nil }
                    return draft
                },
                set: { (next: AppExtensions.EditorDraft?) in
                    guard next == nil, let service = model.appExtensions, let draft = service.editorDraft,
                          draft.sceneID == sceneID
                    else { return }
                    service.dismissDraft(draft)
                }
            ), onDismiss: {
                if scenePhase == .active { Task { await consume() } }
            }) { draft in
                NoteEditorScreen(sharedDraft: draft.editor)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if draft.destinationChanged {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Shared Note Destination Changed", bundle: .module).font(.headline)
                                Text("Review the deck, note type, and fields before adding this note.", bundle: .module)
                                    .font(.subheadline)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.regularMaterial)
                        }
                    }
            }
    }

    private func isCurrent() -> Bool { model.activeProfile == profile && model.store === store }

    private func consume() async {
        guard isCurrent(), model.canHandleExtensionWork, model.waitingDeckLink == nil else { return }
        await model.appExtensions?.consumeNotes(profileID: profile.id, store: store, sceneID: sceneID)
    }
}
