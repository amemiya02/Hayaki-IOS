import CollectionStore
import CollectionTesting
import DeckOptionsFeature
import Testing

/// Opens a deck's options, as tapping "Deck Options" on the deck does.
@MainActor
func openOptions(_ store: CollectionStore, deck: Int64) async -> DeckOptionsModel {
    let model = DeckOptionsModel(store: store, deckID: deck)
    await model.load()
    return model
}

@MainActor
@Suite("Deck options: presets", .timeLimit(.minutes(1)))
struct PresetTests {
    @Test("A deck's options show its name and the Default preset it uses")
    func opensWithDefaultPreset() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Languages::Spanish")
            let model = await openOptions(store, deck: spanish)

            #expect(model.state == .loaded)
            #expect(model.deckName == "Languages::Spanish")
            #expect(model.presets.map(\.name) == ["Default"])
            #expect(model.selectedPreset?.name == "Default")
            #expect(model.hasChanges == false)
        }
    }

    @Test("A new preset is used by the deck once saved, and the other decks keep Default")
    func addPreset() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let french = try await store.addDeck(named: "French")
            let model = await openOptions(store, deck: spanish)

            model.addPreset(named: "  Hard words ")
            #expect(model.selectedPreset?.name == "Hard words")
            #expect(model.hasChanges)
            #expect(await model.save())

            let reopened = await openOptions(store, deck: spanish)
            #expect(reopened.presets.map(\.name) == ["Default", "Hard words"])
            #expect(reopened.selectedPreset?.name == "Hard words")
            #expect(await openOptions(store, deck: french).selectedPreset?.name == "Default")
        }
    }

    @Test("A preset can be renamed; a blank name is ignored")
    func renamePreset() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let model = await openOptions(store, deck: spanish)

            model.renameSelectedPreset(to: "   ")
            #expect(model.selectedPreset?.name == "Default")
            #expect(model.hasChanges == false)

            model.renameSelectedPreset(to: "Everyday")
            #expect(await model.save())

            #expect(await openOptions(store, deck: spanish).presets.map(\.name) == ["Everyday"])
        }
    }

    @Test("A preset is not added or cloned with a blank name")
    func blankNames() async throws {
        try await withTemporaryCollection { store in
            let model = await openOptions(store, deck: try await store.addDeck(named: "Spanish"))
            model.addPreset(named: "")
            model.cloneSelectedPreset(named: "  ")
            #expect(model.presets.map(\.name) == ["Default"])
            #expect(model.hasChanges == false)
        }
    }

    @Test("A cloned preset starts with the options of the one it copies")
    func clonePreset() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let model = await openOptions(store, deck: spanish)
            model.learningSteps = "5m 1h"

            model.cloneSelectedPreset(named: "Spanish steps")
            #expect(model.selectedPreset?.name == "Spanish steps")
            #expect(model.learningSteps == "5m 1h")
            #expect(await model.save())

            let reopened = await openOptions(store, deck: spanish)
            #expect(reopened.presets.map(\.name) == ["Default", "Spanish steps"])
            #expect(reopened.learningSteps == "5m 1h")
        }
    }

    @Test("Choosing another preset for the deck shows how many decks use each")
    func assignPreset() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let french = try await store.addDeck(named: "French")
            let setup = await openOptions(store, deck: spanish)
            setup.addPreset(named: "Languages")
            #expect(await setup.save())

            let model = await openOptions(store, deck: french)
            // A new collection has the Default deck too, so Default is used
            // by Default and French.
            #expect(model.presets.map(\.deckCount) == [2, 1])
            let languages = try #require(model.presets.first { $0.name == "Languages" })
            model.selectedPresetID = languages.id

            #expect(model.selectedPreset?.name == "Languages")
            #expect(model.presets.map(\.deckCount) == [1, 2])
            #expect(await model.save())

            #expect(await openOptions(store, deck: french).selectedPreset?.name == "Languages")
        }
    }

    @Test("Deleting a shared preset moves every deck that used it to Default")
    func deleteSharedPreset() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let french = try await store.addDeck(named: "French")
            let setup = await openOptions(store, deck: spanish)
            setup.addPreset(named: "Languages")
            #expect(await setup.save())
            let assign = await openOptions(store, deck: french)
            assign.selectedPresetID = try #require(assign.presets.first { $0.name == "Languages" }).id
            #expect(await assign.save())

            let model = await openOptions(store, deck: french)
            #expect(model.selectedPreset?.deckCount == 2)
            #expect(model.canDeleteSelectedPreset)
            model.deleteSelectedPreset()

            #expect(model.presets.map(\.name) == ["Default"])
            #expect(model.selectedPreset?.name == "Default")
            #expect(model.selectedPreset?.deckCount == 3)
            #expect(await model.save())

            #expect(await openOptions(store, deck: spanish).selectedPreset?.name == "Default")
            #expect(await openOptions(store, deck: french).presets.map(\.name) == ["Default"])
        }
    }

    @Test("The Default preset cannot be deleted")
    func defaultCannotBeDeleted() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let model = await openOptions(store, deck: spanish)

            #expect(model.canDeleteSelectedPreset == false)
            model.deleteSelectedPreset()
            #expect(model.presets.map(\.name) == ["Default"])
            #expect(model.hasChanges == false)
        }
    }

    @Test("A preset added and deleted before saving leaves nothing behind")
    func addThenDeleteUnsaved() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let model = await openOptions(store, deck: spanish)

            model.addPreset(named: "Draft")
            model.deleteSelectedPreset()
            #expect(model.selectedPreset?.name == "Default")
            #expect(model.hasChanges == false)
        }
    }
}
