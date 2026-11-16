# Feature packages

Nearly all of Hayaki's code lives in local Swift packages under `Packages/`. The app target (`App/HayakiApp.swift`) only shows `AppShell.RootView`.

```
Packages/
  AnkiCore/           Core Client (typed async calls into Anki's core)
  CollectionStore/    CollectionStore library; CollectionTesting library for tests only
  AppShell/           AppModel (opens the collection at launch), RootView, SectionsView (tabs / sidebar)
  DecksFeature/       DeckListModel, DeckListScreen, DecksSection
  BrowseFeature/      placeholder
  StatisticsFeature/  placeholder
  SettingsFeature/    placeholder
  PackagesFeature/    PackageImportModel, the import sheets (packageImport(_:)), ImportPackageButton
  NoteEditorFeature/  NoteEditorModel, NoteEditorScreen; addNoteAction(store:), the shell's Add Note button
  StudyFeature/       StudySessionModel, StudyScreen (presented from Decks with studySession(of:store:)),
                      CardWebView and the card host page Resources/CardHost.html, served with the
                      media folder and the bundled MathJax (WebAssets/) through the
                      hayaki-card:// scheme (CardResources); CardAudioPlayer plays card audio
UITests/              UI tests of the assembled app (HayakiUITests target); see UITestLaunch in AppShell
```

## Where things go

A feature package is named `<Area>Feature` (module and folder alike), so its module never clashes with a SwiftUI type such as `Settings`. Inside it:

- `Sources/<Area>Feature/<Screen>Model.swift`: one `@MainActor @Observable` model per screen. Models depend only on `AnkiCore` and `CollectionStore`.
- `Sources/<Area>Feature/<Screen>Screen.swift` (and private subviews): SwiftUI views using stock components. A section's root screen has its own `NavigationStack`.
- `Sources/<Area>Feature/<Area>Section.swift` for a section shown in the tab bar and sidebar: its `title` and `systemImage`.
- `Sources/<Area>Feature/Resources/Localizable.xcstrings`: every user-visible string of the package, with a comment. In code: `Text("…", bundle: .module)` and `String(localized: "…", bundle: .module)`. The package declares `defaultLocalization: "en"` and `resources: [.process("Resources")]`.
- `Tests/<Area>FeatureTests/`: Swift Testing tests of the models, depending on `CollectionTesting`.

A new feature that is a new package (for example Study, presented from Decks) is added as a dependency of the package that presents it, and listed under `packages:` in `project.yml` so it shows in Xcode. A new section would also be added to `AppShell/Sources/AppShell/SectionsView.swift`; the four v1 sections already exist.

## The Core Client and the Collection Store

Screens are created with the open `CollectionStore` (`DeckListScreen(store:)`), which their model keeps.

- Reads go straight to the Core Client: `try await store.core.deckTree(…)`.
- Every call that modifies the collection goes through `try await store.modify(.someCall(request))`. It runs the call and then signals the change summary the core returned to every subscriber. The response type must conform to `CollectionChanging`; the common ones (`OpChanges`, `OpChangesWithCount`, `OpChangesWithId`, `OpChangesAfterUndo`, `OpChangesOnly`, `AddNoteResponse`, `AddNotesResponse`, `ImportResponse`) already do. Add a conformance for another response type in your own package.
- A model that shows collection data has a `run()` that the screen calls from `.task`: subscribe with `store.changes()` first, then load, then reload whenever a change intersects what the screen shows (see `DeckListModel.run()`). Subscribe inside `run()`, not in `init`: SwiftUI cancels and restarts `.task` when a screen disappears and reappears, and cancelling ends a stream.
- `store.undo()` and `store.undoableAction()` undo the last operation with the core's undo and name it.
- `store.replace { core, location in … }` closes the collection, lets the body overwrite it (a collection package import, a restore), reopens it and signals `.everything`.
- Long operations with progress and cancel: `store.core.start(.call(request))` returns a `LongOperation`; await one that modifies the collection with `store.modify(operation)` so its change is signalled.

## Tests

Tests construct a model over the real core and a throwaway collection and assert what a learner would see; the core is never mocked.

```swift
try await withTemporaryCollection { store in
    let deck = try await store.addDeck(named: "Spanish")
    try await store.addBasicNotes(count: 2, toDeck: deck)
    let model = DeckListModel(store: store)
    await model.refresh()
    #expect(...)
}
```

`CollectionTesting` provides `withTemporaryCollection`, `TemporaryFolder`, `eventually { … }` for models that update in the background, and learner-level setup actions on `CollectionStore` (`addDeck(named:)`, `addBasicNotes(count:toDeck:)`, `answerNextCard(inDeck:rating:)`, `makeDueToday(_:)`, `suspend(_:)`, `deckNames()`). Add new setup actions there, in a new file per area, so they are shared.

Real Anki packages to start from: `FixturePackage` (`.collection`, `.basicDeck`, `.clozeDeck`, `.typedAnswerDeck`) with `url` and `contents` (what each holds), `store.importFixture(_:)` to bring one in, and `store.contents()` to compare a collection with a fixture's description. They were written by the pinned core's own export code (Anki 26.09.4), not by a desktop Anki install; see `FixturePackages.swift` for what they hold and how to regenerate them. Also `addNotes(ofType:fields:toDeck:)`, `addMediaFile(named:data:)`, `cardIDs(matching:)`, `noteIDs(matching:)`, `reviewCount(matching:)` and `mediaFileNames()`.

Run every package's tests with `scripts/test.sh`, or one package with `scripts/test.sh DecksFeature`. A new package with a `Tests` folder is picked up automatically, by the script and by CI.
