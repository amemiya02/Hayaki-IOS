# Hayaki v1: a free, native client for Anki collections on iPhone and iPad

Vocabulary follows `GLOSSARY.md`. Decisions already recorded in `docs/adr/` (0001 to 0004) are binding and are summarised here, not re-argued.

## Problem Statement

A learner who studies with Anki on a computer or on Android has no free way to keep studying on an iPhone or iPad. The official iOS app is paid. The learner wants to open their existing collection on an Apple device, review the cards that are due, add and fix notes, and get their progress back out again, without paying and without their collection being trapped on the device.

A learner who does not use AnkiWeb at all, because they run their own sync server or do not sync, has the same need and no approved client to meet it.

## Solution

Hayaki is a free, open-source, standalone client for iPhone and iPad. It holds the learner's whole collection on the device, works offline, and reads and writes the same collection that desktop Anki and AnkiDroid do, because it embeds the same Anki core they use.

The learner brings a collection in by opening a collection package or deck package, studies with a fully native interface, and takes it out again as a package that AnkiDroid or desktop Anki can import. A learner with their own sync server can sync directly. Hayaki does not sign in to AnkiWeb.

It ships in English, Simplified Chinese and Japanese. It is built from source and installed on the simulator or on the learner's own device; it is not distributed through the App Store.

## User Stories

### First launch and getting a collection in

1. As a new learner, I want Hayaki to open straight into a working empty collection, so that I can start without any setup.
2. As a new learner, I want the first screen to offer to import a package, so that I know how to bring my existing cards in.
3. As an AnkiDroid learner, I want to open a collection package exported from AnkiDroid, so that my decks, review history, scheduling and deck options arrive intact.
4. As a desktop Anki learner, I want to open a collection package exported from desktop Anki, so that I can continue on my iPhone exactly where I stopped.
5. As a learner, I want to be warned before a collection package replaces my current collection, so that I do not lose work by accident.
6. As a learner, I want Hayaki to make a backup automatically before a collection package replaces my collection, so that I can undo the replacement.
7. As a learner, I want to open a deck package, so that its decks are merged into the collection I already have.
8. As a learner, I want to choose how a deck package is merged (whether to bring learning progress, how to treat notes that already exist), so that importing behaves the way it does in Anki.
9. As a learner, I want to see what an import added, updated and skipped, so that I can trust the result.
10. As a learner, I want packages sent to me by AirDrop, saved in Files, or shared from another app to open in Hayaki, so that I do not have to hunt for an import button.
11. As a learner, I want to see progress while a large package imports and be able to cancel it, so that I am never stuck watching a spinner.
12. As a learner, I want the media inside a package (images and audio) to arrive with it, so that my cards look and sound right.

### Decks

13. As a learner, I want to see all my decks as a nested list, so that I can find what to study.
14. As a learner, I want each deck to show how many new, learning and due cards it has today, so that I can decide where to start.
15. As a learner, I want to collapse and expand parent decks, so that a large collection stays manageable.
16. As a learner, I want to create a deck, so that I can organise new material.
17. As a learner, I want to rename a deck, so that I can fix its name.
18. As a learner, I want to delete a deck, with a clear statement of how many cards go with it, so that I do not delete cards by mistake.
19. As a learner, I want to move a deck under another deck, so that I can reorganise.
20. As a learner, I want the deck list to refresh after studying, importing or syncing, so that the counts are always current.
21. As a learner, I want a clear "nothing left for today" state on a finished deck, so that I know I am done.

### Studying

22. As a learner, I want to start studying a deck with one tap, so that reviewing is quick to begin.
23. As a learner, I want to see the question side of a card rendered exactly as its card template defines, so that my cards look as they do in Anki.
24. As a learner, I want to reveal the answer with a tap, so that I can check my recall.
25. As a learner, I want to rate my review as Again, Hard, Good or Easy, so that the card is rescheduled.
26. As a learner, I want each rating button to show the interval it would give, so that I understand the consequence before I tap.
27. As a learner, I want to see how many new, learning and due cards remain in the session, so that I know how far I have to go.
28. As a learner, I want to undo my last review, so that a mis-tap does not damage my scheduling.
29. As a learner, I want to bury a card or its note until tomorrow, so that I can skip it for today.
30. As a learner, I want to suspend a card or its note, so that it stops appearing until I bring it back.
31. As a learner, I want to flag a card with a colour, so that I can find it later in the browser.
32. As a learner, I want to edit the current note without leaving my study session, so that I can fix a mistake when I notice it.
33. As a learner, I want audio on a card to play automatically and to replay on demand, so that I can study listening material.
34. As a learner, I want images on cards to display at a sensible size and long cards to scroll, so that nothing is cut off.
35. As a learner, I want maths written in MathJax to render, so that my science and maths cards are readable.
36. As a learner, I want cloze deletions to work, so that cloze notes are usable.
37. As a learner, I want cards that ask me to type the answer to accept my typing and show the comparison, so that those cards work.
38. As a learner, I want the study screen to be usable one-handed, with rating buttons within thumb reach, so that I can review anywhere.
39. As a learner, I want haptic feedback when I rate a card, so that the action feels confirmed without looking.
40. As a learner, I want cards to follow light and dark mode, so that studying at night is comfortable.
41. As a learner using an iPad, I want the study screen to use the larger display well, so that cards are not stretched or tiny.
42. As a learner, I want a summary when a session ends, so that I know what I accomplished.

### Adding and editing notes

43. As a learner, I want to add a note by choosing a note type and a deck and filling in its fields, so that I can create cards on the go.
44. As a learner, I want Add to be reachable from anywhere in the app, so that capturing a thought is fast.
45. As a learner, I want to attach an image from my photo library to a field, so that I can make visual cards.
46. As a learner, I want to add and remove tags on a note, so that I can organise my notes.
47. As a learner, I want Hayaki to remember the note type and deck I last used, so that adding several notes in a row is quick.
48. As a learner, I want to be told when a note is a duplicate or has an empty first field, so that I do not create broken notes.
49. As a learner, I want to edit an existing note's fields and tags, so that I can correct it.
50. As a learner, I want formatting that already exists in a field to survive my edit, so that editing on the phone never damages a note made on desktop.
51. As a learner, I want to preview the cards a note produces, so that I can check them before studying.
52. As a learner, I want to delete a note, so that I can remove material I no longer need.

### Browsing and searching

53. As a learner, I want to browse all my cards in a list, so that I can find any of them.
54. As a learner, I want to search using Anki's search syntax, so that searches I know from desktop work here.
55. As a learner, I want quick filters for common searches (a deck, a tag, a flag, suspended, due today), so that I do not have to type syntax for everyday needs.
56. As a learner, I want to sort the list, so that I can see for example the most recently added first.
57. As a learner, I want to open a card from the list to see its note, deck, due date and review history, so that I can understand its state.
58. As a learner, I want to select several cards and suspend, unsuspend, flag, move to another deck, or delete them, so that I can tidy up in bulk.
59. As a learner with a very large collection, I want the browser to stay responsive, so that it remains usable with a hundred thousand cards.

### Deck options

60. As a learner, I want to open the deck options for a deck, so that I can control how it is scheduled.
61. As a learner, I want to create, rename and delete presets and assign a preset to a deck, so that several decks can share one set of options.
62. As a learner, I want to set daily limits for new cards and reviews, so that my workload is manageable.
63. As a learner, I want to set learning and relearning steps, so that new and forgotten cards are shown at the intervals I choose.
64. As a learner, I want to turn FSRS on or off and set my desired retention, so that I can use Anki's current scheduler.
65. As a learner, I want to optimise my FSRS parameters from my review history, with progress shown and a working cancel, so that scheduling fits my memory.
66. As a learner, I want to set display order and burying, so that cards appear in the order I prefer.
67. As a learner, I want options I cannot yet edit in Hayaki to be left untouched, so that settings made on desktop are never lost.

### Statistics

68. As a learner, I want a summary of today's studying, so that I can see what I did.
69. As a learner, I want a forecast of cards coming due, so that I can anticipate my workload.
70. As a learner, I want charts of reviews per day and review time per day, so that I can see my habit.
71. As a learner, I want to see how my cards divide between new, learning, young, mature and suspended, so that I understand my collection.
72. As a learner, I want to see how often I choose each rating, so that I can judge my performance.
73. As a learner, I want a calendar heatmap of my studying, so that I can see my streaks.
74. As a learner, I want to view statistics for one deck or for the whole collection, and over different periods, so that I can look at what matters to me.

### Getting a collection out

75. As a learner, I want to export my whole collection as a collection package, so that I can import it into AnkiDroid or desktop Anki and sync it to AnkiWeb from there.
76. As a learner, I want to export chosen decks as a deck package, so that I can share them or move them.
77. As a learner, I want the same export choices Anki offers (include scheduling, include media, support older Anki versions), so that the package suits where it is going.
78. As a learner, I want to send an exported package through the share sheet, so that I can AirDrop it, save it to Files or send it to another app.
79. As a learner, I want a short guide to moving a collection to and from AnkiDroid, so that I know the steps and understand that a collection package replaces rather than merges.

### Sync with a self-chosen sync server

80. As a learner who runs a sync server, I want to enter my server's address, user name and password, so that Hayaki can sync with it.
81. As a learner, I want my password never to be stored, only the key the server issues, kept in the device's secure storage, so that my credentials are safe.
82. As a learner, I want to sync with one tap, so that my devices stay in step.
83. As a learner, I want my media to sync as well, with progress shown, so that images and audio arrive.
84. As a learner, I want to be asked whether to upload or download when the two sides cannot be merged, with each choice explained, so that I do not overwrite the wrong one.
85. As a learner, I want sync to be cancellable and to tell me plainly when it fails and why, so that I am not left guessing.
86. As a learner, I want to sign out of my sync server, so that I can stop syncing or change server.
87. As a learner who does not sync, I want Hayaki to work fully with sync never set up, so that sync is optional.
88. As a learner, I want it stated clearly that Hayaki does not sign in to AnkiWeb and why, so that I do not waste time trying.

### Protecting the collection

89. As a learner, I want Hayaki to back up my collection automatically, so that I am protected without thinking about it.
90. As a learner, I want old backups to be thinned out automatically, so that they do not fill my storage.
91. As a learner, I want to make a backup on demand, so that I can protect myself before a risky change.
92. As a learner, I want my backups and exports to be visible in the Files app, so that I can copy them off the device.
93. As a learner, I want to restore a backup from inside Hayaki, so that recovering does not need another device.
94. As a learner, I want Hayaki to show a recovery screen, not crash, if my collection cannot be opened, so that I can restore a backup or export what is there.
95. As a learner, I want a way to check my collection for problems, so that I can repair it when something looks wrong.
96. As a learner, I want a failure inside the engine to appear as an error message, not an app crash, so that I do not lose my place.

### Reminders, settings and language

97. As a learner, I want a daily reminder at a time I choose, so that I do not forget to study.
98. As a learner, I want the reminder to say how many cards are due, so that it is worth reading.
99. As a learner, I want to turn the reminder off, so that I am not nagged.
100. As a learner, I want Hayaki in English, Simplified Chinese or Japanese following my device language, so that I can use it in my own language.
101. As a learner, I want scheduling text such as rating names and intervals to be in the same language as the rest of the app, so that the language is never mixed.
102. As a learner whose device is in another language, I want Hayaki to fall back to English throughout, so that it is still consistent.
103. As a learner who uses large text or VoiceOver, I want every screen to respect Dynamic Type and to be labelled for VoiceOver, so that Hayaki is usable for me.
104. As a learner, I want an About screen showing the app version, the Anki core version, the licence, credits, and a statement that Hayaki is not affiliated with Anki's makers, so that I know what I am running.

### Layout

105. As an iPhone learner, I want four tabs (Decks, Browse, Statistics, Settings), so that every area is one tap away.
106. As an iPad learner, I want those sections in a sidebar with content beside it, so that the app uses the larger screen properly.
107. As a learner, I want studying to take the full screen, so that nothing distracts from the card.

### Building and contributing

108. As a contributor, I want one documented command to build the Anki core for iOS, so that I can build the app from a clean clone.
109. As a contributor, I want the project file generated from a checked-in description, so that project changes are reviewable and never conflict.
110. As a contributor, I want every push built and tested automatically, so that breakage is caught immediately.
111. As a contributor, I want the README to explain how to install Hayaki on my own iPhone with a free Apple ID, so that I can use what I build.
112. As a maintainer, I want upgrading the Anki core to be a regenerate-and-test step with nothing numbered by hand, so that keeping pace with AnkiDroid is cheap.

## Implementation Decisions

### Identity and distribution

- Display name Hayaki; bundle identifier `io.github.amemiya02.hayaki`, fixed permanently even if the display name changes.
- Licence AGPL-3.0-or-later (ADR 0001). README and About screen carry a non-affiliation notice and credit upstream Anki, AnkiDroid and Amgi.
- Universal app for iPhone and iPad, minimum iOS 26.
- No App Store. Source-only releases for now; an unsigned installable build may be added later. No feature may depend on an entitlement that needs a paid Apple Developer membership (no push notifications, no iCloud).
- One collection per install; there are no profiles.

### Engine

- The app embeds upstream Anki's Rust core at tag `26.09.4`, unpatched, brought in as a pinned git submodule (ADR 0001). It keeps all of the core's translations.
- The compiled core is not committed. A build script produces an XCFramework with slices for iOS devices, the iOS simulator on Apple silicon, and macOS on Apple silicon. The macOS slice exists so the main test suite runs on the host without a simulator.
- Upgrade policy: move the pinned core to a new Anki version when AnkiDroid's stable release does, so packages always exchange cleanly.

### Bridge to the core (deep module: the Core Client)

- A small Rust bridge crate exposes four C functions: open a backend, run a method (service number, method number, request bytes, returning response bytes or error bytes), free a response, close a backend.
- Every call across the boundary is wrapped so that a panic inside the core is caught and returned as an error; the build must not abort on panic.
- Message types are generated from the core's protobuf definitions. The typed Swift call for every method, and the service and method numbers, are generated from the core's own descriptor set at build time. Nothing is numbered or mirrored by hand, because the numbering is not stable between Anki versions.
- All calls into the core run on one dedicated worker thread owned by the Core Client, never on the main thread and never on Swift's shared concurrency pool. The Core Client presents an async interface.
- Long operations (sync, media sync, import, export, FSRS optimisation, collection check) expose progress as an async sequence fed by polling the core's progress call, and support real cancellation through the core's abort call. Progress polling and abort must not queue behind the long operation they refer to.
- Core errors are surfaced as a typed Swift error carrying the core's error kind and its already-localised message.
- The core is initialised with exactly one language: the language the app's own screens resolved to.

### Collection lifecycle (deep module: the Collection Store)

- Owns opening, closing and replacing the collection, and is the only place that knows where the collection and media live on disk. The live collection is private to the app.
- Opening is asynchronous. If it fails, the app shows a recovery screen offering restore from a backup and export of the files as they are.
- Publishes a change signal after every operation that modifies the collection, derived from the change summary the core returns, so feature models refresh only what changed.
- Exposes undo of the last operation using the core's undo.
- Closes or checkpoints the collection when the app goes to the background.

### Feature modules

Each is a local Swift package with an observable model per screen and SwiftUI views; models depend only on the Core Client and the Collection Store.

- **Decks**: deck tree with counts, create, rename, delete, reparent, collapse state.
- **Study**: fetches the next queued card with its scheduling states from the core, obtains interval labels for each rating from the core, submits the answer with the chosen rating; undo, bury, suspend, flag; session counts and end-of-session summary.
- **Card display**: a web view is used only to draw cards (ADR 0004). Card HTML comes from the core's rendering of an existing card. A small host page and script of our own shows the question and answer sides. Media and bundled MathJax are served through a custom URL scheme handler that streams files and honours range requests. Audio is taken from the audio tags the core extracts from the card and played by a native audio queue; replay buttons in the card call back to native code. Typed-answer cards use the core's answer comparison.
- **Note editor**: add and edit notes; fields edited as plain text with existing markup preserved byte for byte when untouched; image attachment from the photo library through the core's media-add call; tags; duplicate and empty-first-field checks from the core; card preview.
- **Browser**: search through the core using Anki's search syntax, sorted; rows fetched in pages so very large collections stay responsive; bulk actions.
- **Packages**: import and export of collection packages and deck packages with the core's options; registered as an opener for both file types; exports leave through the share sheet; a backup is taken before a collection package replaces the collection.
- **Sync**: server address is mandatory and entered by the learner; there is no AnkiWeb option, preset or default (ADR 0002). Login exchanges user name and password for a host key, which is stored in the Keychain; the password is never stored. Normal sync, full upload or download when required, media sync, progress and cancellation. The client identifies itself honestly as Hayaki on iOS, never as another client.
- **Deck options**: native form over the core's deck-configuration calls, covering presets, daily limits, learning and relearning steps, FSRS on/off, desired retention, parameter optimisation, display order and burying. Fields the form does not present are read and written back unchanged.
- **Statistics**: seven Swift Charts views (today, future due, reviews per day, review time per day, card counts by state, rating breakdown, calendar heatmap) computed from the core's graphs data, for a deck or the whole collection, over selectable periods.
- **Backups**: automatic rotating backups through the core's backup call, on-demand backup, restore inside the app, collection check. Backups and exports live in the app's Documents folder, which is exposed to the Files app.
- **Settings**: sync, backups, daily reminder as a local notification, the AnkiDroid transfer guide, About.

### App shell

- Swift 6 language mode with complete strict concurrency. SwiftUI with the Observation framework. No third-party Swift libraries other than Apple's SwiftProtobuf.
- Stock system look: native components with their default iOS 26 and 27 appearance, system colours, dark mode, Dynamic Type, VoiceOver labels. The study screen receives the most design effort.
- iPhone: tab bar with Decks, Browse, Statistics, Settings, and an always-reachable Add action. iPad: the same sections in a sidebar. Studying is presented full screen.
- All user-visible strings live in a String Catalog with English, Simplified Chinese and Japanese. Devices in any other language get English throughout.
- The Xcode project is generated by XcodeGen from a checked-in description; the app target is thin and nearly all code is in local Swift packages.
- CI on GitHub Actions builds the core (cached by pinned core version), builds the app, and runs the tests on every push.

### Delivery order

1. Core builds for iOS; app opens a collection and shows the deck list; CI green.
2. Studying and package import.
3. Adding and editing notes; browser.
4. Sync, backups, export.
5. Deck options, statistics, reminders, translations.

Each milestone is pushed to `main` only when it builds, its tests pass, and it has been checked in the simulator. Pushes are made as the `amemiya02` account.

## Testing Decisions

A good test here drives the app the way a learner would and checks what the learner would see. It does not assert which core methods were called, in what order, or how a model stores its state.

### Seam 1 (primary): feature models over a real collection

- Tests construct a feature model wired to the real embedded core, pointed at a throwaway collection in a temporary directory, perform learner-level actions, and assert the model's observable state and the collection's resulting contents.
- The core is never mocked or faked. It is fast, local and deterministic, and faking it would test our assumptions about Anki instead of Anki.
- These tests run on the Mac host against the macOS slice of the core, using Swift Testing, so the whole suite runs in seconds without a simulator.
- Fixtures are real package files produced by Anki 26.09: a small collection package with review history and media, and deck packages covering basic, cloze and typed-answer note types.
- Covered through this seam: decks, study (queue, ratings, undo, bury, suspend, flags), note editing (including that untouched markup survives), browser search and bulk actions, package import and export, backups and restore, deck options (including that unpresented fields survive a save), statistics data shaping, and collection recovery.
- Package interchange is tested as a round trip: import a fixture, export it, re-import the export into a fresh collection through the core, and compare notes, cards, scheduling, review history and media.
- Sync is tested through the same seam against a real sync server built from the same pinned Anki source and started locally by the test fixture: login, normal sync, forced upload and download, media sync, cancellation, and wrong-credential and unreachable-server failures.
- Assertions about scheduling are relative (the card left the queue, the counts dropped, the interval label matches what the core reports), never absolute dates, so tests do not depend on the clock.
- The only substitutes allowed are at true system boundaries: the notification centre for reminders and the Keychain for the host key.

### Seam 2 (thin): the running app in the simulator

- A small set of UI tests for behaviour that exists only in the assembled app: a card with an image, audio and MathJax draws in the web view; revealing and rating a card advances the session; a package opened from outside the app starts an import; the four sections are reachable on iPhone and iPad layouts; the three languages load.
- Kept deliberately few. Anything that can be asserted through seam 1 is tested there.

### Not unit-tested separately

- The generated call layer and the bridge are exercised by every seam 1 test. One additional test checks that a panic provoked inside the core surfaces as an error and leaves the app able to make further calls.

### Prior art

- This repository has no tests yet. The model to follow is AnkiDroid's practice of testing against the real backend, and Amgi's live-backend tests; the difference is that ours run in CI on every push.

### Manual check owed by the project owner

- Importing a Hayaki export into a real AnkiDroid install and syncing it to AnkiWeb from there, and the reverse.

## Out of Scope

- Signing in to or syncing with AnkiWeb (ADR 0002).
- App Store or TestFlight distribution.
- Reusing upstream Anki's web pages for any screen (ADR 0004).
- Card template editor; note type and field management.
- Filtered decks and custom study.
- Image occlusion editing.
- Text-to-speech; audio recording into fields.
- Rich-text editing of fields.
- Widgets, whiteboard, customisable gestures, a watch app.
- A browser for downloading shared decks.
- Multiple collections or profiles.
- Traditional Chinese and any language beyond the three listed.
- Deck options left for later: FSRS simulator, easy days, auto-advance, timers and audio options, custom scheduling code.
- Statistics left for later: intervals, hourly breakdown, true retention, FSRS difficulty, stability and retrievability distributions.
- Compatibility with AnkiDroid's or AnkiMobile's JavaScript APIs for card templates. Ordinary card scripts run; client-specific APIs are not provided.
- Publishing the compiled core as a downloadable release for contributors without Rust.

## Further Notes

- **Unproven until milestone 1:** building the core at `26.09.4` for iOS has been done by another project at an older Anki version, not yet here. Known pitfalls from that project: the descriptor-set path must be passed explicitly to the build, stripping the binary can corrupt it, and a static library interferes with SwiftUI previews.
- **To confirm while building import:** how a deck package import treats the scheduling of cards that already exist in the collection. The transfer guide's wording depends on it.
- **File types:** the identifiers used to register as an opener for collection packages and deck packages need checking against what Anki's own apps declare.
- **Name:** an unrelated app called "Hayaki: Learn Languages Fast" exists on the App Store. Because the bundle identifier is fixed and independent of the name, renaming remains a one-line change.
- **The core's interface is not a public API.** Upstream says so explicitly. Everything generated from it is regenerated on each upgrade and deck options and statistics are re-checked against upstream then (ADR 0001, ADR 0004).
- **Assumed from the final design round, not individually confirmed:** the bundle identifier above, the AnkiDroid interchange checks as v1 requirements, and the policy of following AnkiDroid's stable Anki version.
