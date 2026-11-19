# iOS parity acceptance

Android baseline `0f5dc353fb424751d74ba7d315457b62d95348a7` (19 November 2026), including source changes after the gallery. This inventory tracks [#25] for the [parity parent][#1]. The [specification](hayaki-v1.md) defines completion. The [ticket inventory](ios-parity-tickets.md) preserves feature ownership and the scope of earlier issues. [Pinned product][product] · [97 Android screen states][gallery] · [Pinned study behavior][study-source]

The walkthrough records iOS routes inspected in source. Each issue number also identifies the fixture, observed results and pending acceptance checks in [Feature evidence](#feature-evidence). Results apply to the revision and environment recorded with each result. Keep pending checks open until the relevant behavior is observed, and record platform decisions under [#1].

## Integrated build and device evidence

| Revision | Observed result | Acceptance still open |
| --- | --- | --- |
| `4ea1099` | GitHub CI built the embedded core from a clean checkout, passed the macOS test step using a cached local sync server, generated the project and built the unsigned simulator app. On iPad landscape, `NavigationUITests` passed both cases. They created and renamed a nested deck, checked due and studied summaries, reached all four destinations, retained Vocabulary selection through navigation and the Files picker, then resumed the selected reviewer. The iPhone XCTest runner exited during bootstrap before test assertions. [Run 44530950322][ci-first] · [Navigation test](../../UITests/NavigationUITests.swift) | Phone tabs, portrait and compact iPad, broader iPad interactions and signed-device installation. |
| `51e76e8` | GitHub CI passed the macOS test, project generation and unsigned app build steps using cached core and server outputs. The simulator step was still running when checked. [Run 44538876433][ci-retry] | Record the phone and tablet test results when available. This revision precedes the final feature merges. |
| `905ea36` | The follow-up integration run was queued behind the active run. [Run 44545812392][ci-follow-up] | Record the results when available. |
| `5260c16` | Both XcodeGen commands succeeded in a fresh worktree. The regular Hayaki app target embeds Share and WidgetKit. The personal overlay omits both from the Hayaki app target and clears its App Groups entitlement. [Build instructions](../../README.md#building) · [Default spec](../../project.yml) · [Personal overlay](../../project-personal.yml) | Repeat source build and installation according to the guide for both signing configurations. Verify the app launches, opens a collection, and returns from Files on iPhone and iPad. Check external entry points with the corresponding provisioning. |

## Fixtures

Use disposable copies. Fix the time zone, study-day cutoff, scheduler and period before comparing counts, dates or charts. Record the app commits, core version, fixture digest, device and OS, language, appearance and window size with each result.

| Fixture | Use and expected baseline |
| --- | --- |
| **Fresh** | Fresh install or isolated app data with no prior Welcome choice. Exercise start empty, package/text import, shared decks and sign-in individually. Relaunch after each and check the saved route. |
| **Study** | Use the checked-in `collection.colpkg` plus the matching `basic.apkg`, `cloze.apkg` and `typed-answer.apkg`. The collection contains 8 notes, 9 cards, 4 reviews, and the original image and M4A. Study Spanish for image/audio, Geography for cloze/MathJax and Vocabulary for typed answer. Use the same file on Android and iOS. [Fixture definitions](../../Packages/CollectionStore/Sources/CollectionTesting/FixturePackages.swift) |
| **Queues and graphs** | Use Study or parallel deterministic seeds. Include new, learning-due-later, review, overdue, buried and suspended cards, entries on both sides of cutoff, a nested deck and a tagged subset. Seed the same prior review timestamps and ratings, including an old entry outside one year. Compare counts and intervals after the same sequence of answers and filters. For FSRS optimization, also use a disposable history meeting the pinned core's minimum. [Finished cases](../../Packages/StudyFeature/Tests/StudyFeatureTests/FinishedStudyTests.swift) · [Statistics fixtures](../../Packages/StatisticsFeature/Tests/StatisticsFeatureTests/StatisticsModelTests.swift) · [FSRS fixtures](../../Packages/DeckOptionsFeature/Tests/DeckOptionsFeatureTests/FSRSTests.swift) |
| **Edit and media** | Use Study with a duplicate, a long deck title, a long card, markup, formatting and tags. Import the desktop markup package for formatted fields. Use a known image and audio clip for edit/occlusion. Check cancellation, unchanged field bytes, stored media and generated cards after reopening. [Markup package](../../Packages/NoteEditorFeature/Tests/NoteEditorFeatureTests/Fixtures/desktop-markup.apkg) · [Occlusion tests](../../Packages/NoteEditorFeature/Tests/NoteEditorFeatureTests/ImageOcclusionTests.swift) |
| **Scripts** | Import `template-scripts.colpkg`. Use the same template on Android and on iOS. Check side/queue, reveal/rating, gated access, stale side and process recreation. [Script fixture](../../UITests/Fixtures/template-scripts.colpkg) · [iOS test](../../UITests/TemplateScriptingUITests.swift) |
| **Transfer and recovery** | Use the four digest-identified exports from the Android evidence when available, current and compatibility exports from iOS, and duplicate CSV/TSV data containing headers, tags and HTML. The pinned Android round-trip directory records the measurements and screenshots. To repeat the exchange without the original packages, generate fresh Android exports and record their counts and digests before import. Give the destination a sentinel note and existing media. After merge, replacement, restore and cancellation, compare note GUIDs, fields, tags, card scheduling, review entries, options and media SHA-256. Introduce one unused file, one broken reference and a damaged collection in disposable copies for maintenance. [Android procedure, digests and expected counts][round-trip] · [Host round trip][e26] · [Transfer tests](../../Packages/PackagesFeature/Tests/PackagesFeatureTests) |
| **Sync** | Use two profile IDs, disposable collections, distinct media and local upstream sync server data. Test conflict, force-upload/download, interruption during media, relaunch and scope change. Use an isolated AnkiWeb test collection for live hosted acceptance. [Pinned server build](../../scripts/build-sync-server.sh) · [Sync tests](../../Packages/SyncFeature/Tests/SyncFeatureTests/SyncTests.swift) |
| **System entry** | On an iOS installation with App Groups, give two profiles distinguishable deck names and different due counts. Share a multi-line selection containing HTML-significant characters. Configure both widgets and create a timed deck reminder. Switch profile and cold-launch from each destination. Confirm the draft, editor, study, deck options and snooze routes reach the intended profile and deck. Use the personal build to check notification delivery and return with local reminders. [Model tests](../../Packages/AppShell/Tests/AppShellTests/ExtensionIntegrationTests.swift) |

## Android walkthrough

Sheet numbers open the pinned English sheets. The gallery also includes Chinese and Japanese captures. Confirm the iOS outcomes in English, Simplified Chinese and Japanese, and check Light, Dark and Black where the route is visible.

### Welcome, Decks and study

| Sheet | Android state | iOS route and expected result | Owner |
| --- | --- | --- | --- |
| [01] | Welcome | Fresh collection opens Welcome with start empty, import, shared decks and sync. | [#27] |
| 01 | Welcome migration | More → Transfer Guide and the Welcome package action. | [#23] |
| 01 | Decks | Decks tab or sidebar with due counts, nested decks and Study Now. | [#27] |
| 01 | More | More tab or sidebar, retaining the selected deck on return. | [#27] |
| [02] | Statistics | Stats tab → scope, deck/search and period. The toolbar exports a PDF. | [#21] |
| 02 | Decks overflow | Decks toolbar's secondary actions for packages, text and shared decks. | [#27] |
| 02 | Decks add menu | New Deck and the Add Note action on Decks. | [#27] |
| [03] | Deck actions | Control-click or long-press a deck. The list retains selection. | [#27] |
| 03 | Study options | Decks opens the reviewer directly. Deck settings and custom study are in the deck menu. | [#8] |
| 03 | Study question | Decks → study → the question side of the native reviewer. | [#7] |
| 03 | Study answer | Show Answer → four rating choices and core-computed intervals. | [#7] |
| [04] | Reviewer actions | Reviewer toolbar and Study Actions with mark, flag, edit and queue actions. | [#8] |
| 04 | Finished | Finished reviewer explains the queue, lists return time and offers the corresponding next action. | [#8] |
| 04 | Custom study | Deck menu → Custom Study or the finished reviewer → Custom Study. The result opens in the existing reviewer. | [#28] |
| 04 | Custom study preview configuration | Custom Study → Preview New Cards and number of days. | [#28] |
| [05] | Deck options | Deck menu → Deck Options, including presets, limits and FSRS. | [#19] |
| 05 | Filtered deck options | New Filtered Deck from Decks or Browse. Edit from the filtered deck menu. | [#28] |
| 05 | Filtered deck secondary filter | Filtered Deck → enable secondary search and set its order and limit. | [#28] |
| 05 | Card info | Browse row → Card Info, or the reviewer action. Scheduling, history and available FSRS curve. | [#31] |
| [06] | Reviewer whiteboard | Reviewer Study Actions → Whiteboard. Draw with finger or Pencil. | [#29] |
| 06 | Reviewer whiteboard actions | Whiteboard toolbar for color, eraser, hide and PNG sharing. | [#29] |
| 06 | Text-to-speech voices | More → Reviewer → Text-to-Speech Voices. Template speech uses installed system voices. | [#29] |

### Browse and note editing

| Sheet | Android state | iOS route and expected result | Owner |
| --- | --- | --- | --- |
| [07] | Browse | Browse tab or sidebar, with cards and notes modes. | [#31] |
| 07 | Browse search | Browse search bar with Anki query syntax. | [#31] |
| 07 | Browser state filter | Browse filter or saved searches. | [#31] |
| 07 | Browser selection | Browse selection with cross-page card or note bulk operations. | [#31] |
| [08] | Browse columns | Browse options → Columns and Sort. Columns, order and sort persist for each row mode. | [#31] |
| 08 | Note editor | Browse detail → Edit Note, or Study Actions → Edit. | [#11] |
| 08 | Editor toolbar layout | Editor formatting and attachment tools. | [#11] |
| 08 | Preview question | Editor toolbar → Preview opens the draft's question. | [#11] |
| [09] | Preview answer | Preview → Show Answer. No collection mutation is needed. | [#11] |
| 09 | Editor multimedia menu | Editor attachment menu for Files, camera, drawing and recording. | [#32] |
| 09 | Editor audio recording | Editor attachment menu → Record Audio. | [#32] |
| 09 | Editor audio saved | Apply the recorded audio to insert a sound reference in the field. | [#32] |
| [10] | Editor drawing | Editor attachment menu → Draw. | [#32] |
| 10 | Editor image preview | Tap the field image or open the attachment controls. | [#32] |
| 10 | Editor image crop | Image preview → Crop. | [#32] |
| 10 | Editor cropped preview | Confirm the crop and inspect the replacement draft attachment. | [#32] |
| [11] | Image occlusion | Editor → Image Occlusion → choose image and add masks. | [#32] |
| 11 | Instant note | System share sheet → Add to Hayaki → Quick Add or Full Editor. Save queues the draft in the displayed profile. Done returns to the sender. | [#37] |

### Note types and templates

| Sheet | Android state | iOS route and expected result | Owner |
| --- | --- | --- | --- |
| [12] | Note Types | More → Note Types. | [#33] |
| 12 | Note Type fields | Select a note type → Fields. | [#33] |
| 12 | Note Type field actions | Field editor for rename, options, reordering and confirmed deletion. | [#33] |
| 12 | Card Template editor | Note type → Card Templates. | [#33] |
| [13] | Card Template actions | Template editor actions for add, duplicate, reorder and remove. | [#33] |
| 13 | Card Template preview · Question | Template editor → Preview → Question. | [#33] |
| 13 | Card Template preview · Answer | Template editor → Preview → Answer. | [#33] |
| 13 | Card Template browser appearance | Template editor → browser front/back templates. | [#33] |
| [14] | Change Note Type | Browse selection or note editor → Change Note Type. | [#33] |
| 14 | Change Note Type mappings | Map fields and templates before applying. Verify required one-way sync where applicable. | [#33] |

### Settings

| Sheet | Android state | iOS route and expected result | Owner |
| --- | --- | --- | --- |
| [15] | Settings | More → Search Settings or select a destination. Localized search matches titles and related terms. | [#38] |
| 15 | Settings · General | More → General for Language, deck defaults, clipboard PNG and Browse media filenames. Language opens iOS app settings. | [#38] |
| 15 | Settings · Appearance | More → Appearance for System, Light, Dark, Black, system night palette and a profile-specific deck background. | [#38] |
| 15 | Settings · Studying | More → Reviewer for scheduling, timer, controls and display. Per-deck overrides are in Deck Options. | [#38] |
| [16] | Settings · Reviewer toolbar | More → Reviewer → toolbar position, order and action visibility. | [#29] |
| 16 | Settings · Timebox | More → Reviewer → review time limit and remembered duration. Deck timer and limits use the core preset. | [#29] |
| 16 | Settings · Controls | More → Reviewer → Controls for touch, keyboard and controller bindings. | [#29] |
| 16 | Settings · Control binding | Reviewer → Controls → edit separate question and answer bindings. | [#29] |
| [17] | Settings · Control gesture | Reviewer → Controls → tap zones, gestures and swipe sensitivity. | [#29] |
| 17 | Settings · Control key | Reviewer → Controls → keyboard and controller inputs exposed by iOS. | [#29] |
| 17 | Settings · Accessibility | More → Accessibility for Browse text size. Reviewer for zoom, timing and answer controls. Exercise Dynamic Type, VoiceOver and Reduce Motion. | [#38] |
| 17 | Settings · Sync | More → Sync for automatic sync, status badge, metered connections, media and timeout. More → Profiles changes the active profile. | [#35] |
| [18] | Settings · Sync server | Sync → choose AnkiWeb or configure a self-hosted URL and its optional PEM certificate. | [#36] |
| 18 | Settings · Review reminders | More → Deck Review Reminders for configurable All Decks and deck-specific rules. More → Daily Reminder for the original single-time reminder. | [#37] |
| 18 | Settings · Backups | More → Backups, retention and selected restore. | [#15] |
| 18 | Settings · Advanced | More → Advanced for line breaks, typed-answer focus and Card Template Permissions. More → Manage Space for collection storage. | [#38] |
| [19] | Settings · About | More → About, project identity and versions. | [#23] |
| 19 | Changelog | More → About → Changelog. | [#23] |
| 19 | Settings · Developer | More → Developer Options in debug builds for opt-in WebKit inspection. Android stress and recovery tools require an owner decision. | [#38] |
| 19 | Settings · Switch profile | More → Profiles → select, add or rename a profile. | [#35] |

### Transfer and storage

| Sheet | Android state | iOS route and expected result | Owner |
| --- | --- | --- | --- |
| [20] | Deck package import | Welcome or Decks → Import a Package. Choose an `.apkg` and set the merge options. | [#34] |
| 20 | CSV import | Welcome or Decks → Import Text File, or open CSV/TSV from Files. | [#34] |
| 20 | Import collection replacement | Open a `.colpkg` and confirm replacement. Hayaki backs up the current collection before replacing it. | [#34] |
| 20 | Export deck | Decks or Browse → Export → Deck Package. | [#34] |
| [21] | Export collection | Decks → Export → Collection Package and compatibility switches. | [#34] |
| 21 | Collection permissions | Application Support stores collection privately, with permitted backup/export folders in Files. | [#15] |
| 21 | Permissions | iOS settings hold system permission choices. App-specific controls use More. | [#38] |
| 21 | Manage space | More → Manage Space with collection and media storage. | [#15] |
| [22] | Media check confirmation | More → Manage Space → Check Media and confirmed removal. | [#15] |
| 22 | Media check | Manage Space lists missing and unused media, with trash recovery. | [#15] |
| 22 | Shared decks | Welcome or Decks → Get Shared Decks → Browse AnkiWeb. | [#34] |
| 22 | Shared decks download | System browser downloads the package. Files opens it in the same merge flow. | [#34] |

### Sync, reminders and widgets

| Sheet | Android state | iOS route and expected result | Owner |
| --- | --- | --- | --- |
| [23] | Sync sign in | Welcome or More → Sync → AnkiWeb or self-hosted sign-in. | [#36] |
| 23 | Sync account | More → Sync for the active profile. | [#35] |
| 23 | Sync conflict | Sync detects the conflict and offers one-way choices. | [#35] |
| 23 | Sync one way | Sync offers force upload or download with confirmation. | [#35] |
| [24] | Sync replace | Sync confirms replacement before collection download. | [#35] |
| 24 | Sync unreachable | Sync reports an unreachable server and preserves credentials/destination. | [#35] |
| 24 | Deck review reminders | More → Deck Review Reminders or deck context menu → Review Reminders. Disabled and unavailable-deck rules remain visible. | [#37] |
| 24 | Review reminder editor | New Reminder or select a rule. Set enabled, threshold, count types and only-if-no-reviews. Reopen and verify the choice. | [#37] |
| [25] | Review reminder time | Review Reminder → native time picker. Verify the local day and delivered time. | [#37] |
| 25 | Review reminder deck picker | Review Reminder → Deck offers All Decks and individual decks. New reminders from More default to All Decks. The deck context menu starts with that deck. [Android editor][android-reminders] | [#37] |
| 25 | Review reminder troubleshooting | Deck Review Reminders explains a denial and offers Open Settings. Confirm the saved rule schedules after permission is restored. | [#37] |
| 25 | Review reminder notification | Tap a delivered alert from a cold start. All Decks opens the originating profile’s deck list. A deck-specific alert opens that deck’s reviewer. Verify 5-minute and 1-hour snooze actions. | [#37] |
| [26] | Home screen widgets | Add Hayaki from the iOS Home Screen widget gallery and use Edit Widget. Verify the counts after a review and the links after profile switching. | [#37] |
| 26 | Widget deck list config | Configure Deck List with up to five decks. Header opens Decks. A row opens the reviewer for a deck with work or Deck Options otherwise. | [#37] |
| 26 | Widget one deck config | Configure One Deck with a deck from the active profile. The stored selection and route carry its profile ID. | [#37] |

## Feature evidence

Use the walkthrough and the fixture in the same row. Host results refer to feature-level runs with the embedded core where the test needs a collection. The record distinguishes completed tests from iOS builds that compiled XCTest cases.

| Owner and fixture | Observed | Open acceptance |
| --- | --- | --- |
| [#7] · Study · Edit and media | Host tests cover card resources, audio order, cloze, typed answers and themed HTML. The reviewer UI suite includes image, maths, audio controls, typed answer and long scrolling. [Ticket evidence][e7] · [UI test](../../UITests/CardContentUITests.swift) | Observe both card sides and precise cloze/answer comparison, template night classes and long-card scrolling. Listen for offline automatic and manual replay in the expected order on both devices. |
| [#8] · Queues and graphs | The combined reviewer/scripting run passed 42 host tests and built the iOS tests. The real core distinguished pending learning, daily limits, buried and finished filtered states. Tests preserved the displayed answer during eligible edits and advanced after Browse suspended the card. [Ticket evidence][e8] | Compare queue, counts, next return time and intervals following undo, redo, flag, mark, bury/suspend, date edits and relaunch. Check one-handed controls and interruption while the answer is visible. |
| [#11] · Edit and media | Host editor tests passed for editing untouched markup fields, tags, sticky fields, preview, cancel and confirmed deletion. The iOS UI tests cover returning from the editor to the same answer or selected Browse row. [Ticket evidence][e11] · [UI test](../../UITests/StudyUITests.swift) | Observe both return paths and verify validation, repeated entry and field bytes after reopening on Android. |
| [#15] · Transfer and recovery | Real-core tests covered manual and automatic backup, preservation of other settings during retention changes, confirmed restore, missing/unused media, media trash, and startup recovery with the damaged file retained. #35 subsequently exercised backup isolation. [Ticket evidence][e15] · [Profile evidence][e35] | Verify Files visibility and the startup recovery sheet on devices. Compare restored options and history and confirm restore/cancel cannot access the other profile. |
| [#17] · Sync | All 25 SyncFeature tests passed for the media-sync slice using the local upstream server. Tests included upload/download, cancellation with the collection still usable, relaunch after media failure and reconciliation on switching destination. [Ticket evidence][e17] | Observe device progress, network interruption/retry and returning from another screen. Exercise live hosted media separately under #36. |
| [#19] · Queues and graphs | The initial suite passed 33 real-core tests for preset preservation, daily limits, no-change saves, per-deck overrides, optimization, cancellation, insufficient history and simulation. The inline estimates follow-up passed 35 tests, including retention factor and history cutoff. [Initial evidence][e19] · [Follow-up][c19] | On both clients, edit, save and reopen each conditional section and compare option values and simulator output for the same input. Verify actual reviewer use of saved settings, including custom scheduling, with #29. |
| [#21] · Queues and graphs | All 15 real-core statistics tests passed, including a readback of native PDF export and scoped graph data. Coverage includes Today, forecast/backlog, calendar, review counts/time, card counts, intervals, ease, stability, difficulty, retrievability, true retention, hourly breakdown, ratings and added. [Ticket evidence][e21] | Compare the same deck/search filters, period, zones, chart selections and empty states across apps. Verify spoken chart values, appearance and Files export on devices. |
| [#23] · Fresh · Transfer and recovery | The in-app transfer guide, Help and About compile into the app. The build stamps the pinned FSRS version and build date from its inputs. About can copy that information with the app, core and platform versions. Core and shell tests ran on the host. [Ticket evidence][e23] · [UI test](../../UITests/HelpAndAboutUITests.swift) | Follow each import, export, sync, help and identity link on devices. Verify the displayed app/core versions and license against the build. |
| [#24] · Study · Edit and media | Japanese and Simplified Chinese catalogs, permission descriptions and fallback tests were added. Five targeted core/fallback tests and eleven reminder tests passed on the localization branch. The integrated unsigned simulator test build compiled `LocalizationUITests`, covering language launches, interval glyphs, RTL mirroring and large-text Decks counts. [Localization merge][c24] · [UI test](../../UITests/LocalizationUITests.swift) | Run the UI tests and perform actual Settings language changes/relaunch. Check RTL, app-owned and system extension text, and delivered notifications after a language change on iPhone and iPad. |
| [#25] · All fixtures | Source inventory and XcodeGen paths audited. Hosted iPad landscape passed two scenarios at `4ea1099`. [Hosted evidence][ci-first] | Execute the device matrix below, including iPhone, iPad portrait and compact window, VoiceOver, Dynamic Type, contrast, touch targets and interruption/resume. Finish signed installation verification. |
| [#26] · Transfer and recovery | Four SHA-256-identified Hayaki Android and AnkiDroid exports matched the expected counts through iOS host model import and re-export/re-import. Scheduling, note data, history and media bytes matched, including the original WebP images and 3GP recording in full collections. The reverse path imported the iOS packages in the actual Hayaki Android and AnkiDroid UI. Full collection fields, card state, history, presets and media matched exactly. Each deck merge preserved fields, template HTML, CSS, history, preset, media and the absolute due date, with an expected Basic+ rename and collection-relative due rebase. [Android baseline][round-trip] · [Host imports][e26] · [Android receipts][e26-reverse] | Run Files merge/replacement and exports on an iOS device. Verify upgrade and profile preservation, plus the dedicated AnkiWeb check. |
| [#27] · Fresh and Study | AppShell and DecksFeature host runs passed 21 tests. The hosted iPad landscape run exercised nested deck creation/rename and all four destinations, preserving the selected reviewer through navigation and the Files picker. [Ticket evidence][e27] | Walk the Welcome choices, tabs, sidebar, narrow iPad and both orientations, including counts and state restoration. Exercise cold launch from Files with a real package. |
| [#28] · Queues and graphs | Real-core tests verify preview without a scheduling change, rescheduling with due-date updates and rebuild after completion. [Ticket evidence][e28] | Set both searches, order and limits. Compare empty/filter results and original due dates on Android and iOS after preview, reschedule, empty and rebuild. |
| [#29] · Study · Queues and graphs | The reviewer control/tool slice passed 38 host tests and built for iOS. Tests wrote and decoded a whiteboard PNG. The custom scheduling follow-up passed 44 StudyFeature tests and compiled the iOS test target. [Initial evidence][e29] · [Follow-up][c29] | Verify touch zones, keys, controller, Pencil, voice selection and playback, recording/permissions, timers and auto-advance. Compare reviewer effects and clean exits with real hardware. |
| [#30] · Scripts | The AnkiDroid 0.0.3 bridge and fixture compiled. Real-core tests covered reveal, rate, stale-side rejection and permission choices. Recreating a WebKit process has a source path to re-register the document. [Ticket evidence][e30] | Execute the portable fixture on Android and iOS. Verify authorized speech/microphone behavior, denied access, preview restrictions and recovery after a terminated WebKit process. |
| [#31] · Study · Edit and media | 33 Browse and 9 export host tests passed. Includes 100,000 cards, cross-page operations and undo, selected text and deck package export, and Card Info. Preview adds side and card navigation, mark, flag, edit, answer-only mode, media replay and its own keyboard, controller and gesture bindings. [Ticket evidence][e31] · [Preview implementation](../../Packages/BrowseFeature/Sources/BrowseFeature/BrowserPreviewScreen.swift) | Compare filters, saved searches, ordering, Card Info, bulk operations, responsive paging and preview input on the same device fixture. |
| [#32] · Edit and media | 34 host editor tests passed. A core package round trip preserved one image, two masks and both generated cards. The iOS build passed. [Ticket evidence][e32] | Use camera, Photos, Files, microphone and Pencil. Inspect crop and mask editing, undo/cancel and audible playback. Open the exported masks in a live Android reviewer. |
| [#33] · Edit and media | 29 editor and four app-shell host tests passed. A round trip preserved mapped fields, formatting and a 12-day review interval. iOS stores the keyboard-language hint with the note type. [Ticket evidence][e33] | Verify field/template settings, preview variants and destructive confirmations in both apps. Compare a one-way conversion and verify hint preservation with the system keyboard switcher. |
| [#34] · Transfer and recovery | 34 PackagesFeature and 12 AppShell host tests passed, including duplicate policies, deck-scoped text, cold CSV handoff and profile isolation. [Ticket evidence][e34] | Exercise external Files opening, shared-deck browser download and native merge, and exporting/importing both current and older formats on devices. |
| [#35] · Sync · Transfer and recovery | AppShell and SyncFeature tests cover profile preference isolation and relaunch, pending work, independent backups, failed destination changes and preservation of prior installation data. [Ticket evidence][e35] · [Profile tests](../../Packages/AppShell/Tests/AppShellTests/ProfilesTests.swift) | Verify profile switching, startup recovery, sync settings and Keychain on device. Test a cold switch during interrupted sync and both confirmed one-way choices. |
| [#36] · Sync | New profiles let the unmodified Anki core choose its AnkiWeb endpoint. The local upstream sync server tests cover legacy account decoding, destination switching and a custom certificate scoped to a self-hosted sign-in. [Ticket evidence][e36] · [UI test](../../UITests/SyncDestinationUITests.swift) | Check the destination picker on device and complete live AnkiWeb sign-in, incremental and forced transfers, conflict, media, sign-out and switching to a self-hosted endpoint. |
| [#37] · System entry | The unsigned UI test build embedded both extensions. ReminderFeature passed 18 host tests, including All Decks thresholds, review-day suppression, profile isolation and snooze. AppShell tests cover shared note capture, editor cancellation and cold routes to a profile’s deck list or reviewer. ExtensionBridge tests cover profile-scoped links and share handoff. [Extension merge][c37] · [Reminder tests](../../Packages/ReminderFeature/Tests/ReminderFeatureTests/ReminderModelTests.swift) · [Shell tests](../../Packages/AppShell/Tests/AppShellTests/ExtensionIntegrationTests.swift) | Verify App Groups provisioning, real host app share/return, widget intent UI and timeline refresh, notification/banner permissions, both snooze actions and foreground/cold routes. |
| [#38] · Study · Edit and media · Fresh | Host checks passed for palette/available contrast and appearance persistence, per-profile backgrounds, localized settings search, atomic scheduling preferences, current-deck defaults, clipboard PNG/line breaks and Browse media filenames. The unsigned app built. [Preferences merge][c38] · [Appearance tests](../../Packages/HayakiAppearance/Tests/HayakiAppearanceTests/AppearanceTests.swift) · [Settings tests](../../Packages/SettingsFeature/Tests/SettingsFeatureTests) | Compare all palettes in native screens and card templates, system palette transitions, language/RTL, accessibility settings and native file/paste/permission surfaces. Confirm available developer tools and About metadata on iOS. |

## Controls and edge cases outside the gallery

| Area | Pinned behavior and iOS check | Owner |
| --- | --- | --- |
| Scheduling | Exercise per-preset, deck and today limits, inherited overrides, learning steps, first-day cutoff, sibling burying, audio replay, visible timer, auto-advance, Easy Days, FSRS/legacy conditional fields and collection custom scheduling. Verify that saved but untouched settings survive and that preview/rescheduling modes consume the intended queue. [Shared options source][core-options] | [#8] · [#19] · [#28] · [#29] |
| Browser and preview | Use Cards and Notes with reversed siblings, current filters, per-mode columns and sorting. Compare scoped find/replace, undo, selection across pages, preview controls and search-derived filtered decks. Validate large-list responsiveness on device. | [#29] · [#31] |
| Storage and upgrade | Retention and automatic backup, failure to open, restoring after backup and media trash recovery. Compare the original store and account after upgrade. Scope every later read/write to the selected profile. | [#15] · [#26] · [#35] |
| Sync policy | Native sync preferences are per profile. Decks shows collection sync status. Local upstream server tests cover foreground cooldown, background changes and media-only sync, metered confirmation, configured timeout and custom TLS trust. On iPhone and iPad, verify the lifecycle and sync UI over unmetered, metered and Low Data Mode connections. [Android preferences][android-prefs] · [Sync policy tests](../../Packages/SyncFeature/Tests/SyncFeatureTests/SyncPolicyTests.swift) | [#17] · [#35] · [#36] |
| Appearance and layout | Confirm priority for explicit Light, Dark and Black, system Dark/Black choice, semantic labels, template night classes, locale typeface, contrast, per-profile backgrounds, Reduce Motion and accessibility-size reviewer controls. | [#24] · [#25] · [#38] |
| Extensions | Validate active-profile selection, shared raw text escaping, multiple queued drafts and cancellation, widget refresh and unavailable profiles, threshold and count-type rules, notification permission changes, all-decks support and snooze behavior. | [#37] |

## Settings defaults and persistence

Start with the Fresh fixture, then reopen after changing each setting. Include two profiles wherever a setting belongs to a collection. Check device preferences independently of package exchange. [Android preference implementation][android-prefs] · [Reviewer behavior][study-source]

| Area | Pinned Android default or edge case | iOS check | Owner |
| --- | --- | --- | --- |
| General | System language, clipboard PNG off in the core, current deck for new cards, Browse audio filenames hidden | More → General. Switch language via iOS Settings and relaunch. For both deck preferences verify normal, note-type and filtered-deck add routes. Paste an image and reopen a card with a sound tag. | [#24] · [#38] |
| Appearance | System, Dark in system night mode, no background | More → Appearance. Explicit Dark and Black update the stored night choice. Replace/remove a deck image and switch profiles. Review deck counts over that background. | [#38] |
| Reviewer scheduling | Study day starts four hours after midnight. Learn ahead 20 minutes. Timebox off, 20 minutes on first enable | More → Reviewer. Edit and reopen each value. Turning the timebox off preserves its last duration for the next enable. Verify scheduling through the core and returned interval/time. | [#29] · [#38] |
| Reviewer display | Keep screen on and vertical centering off. Card frame, feedback, counts, audio play controls, rating buttons and intervals on. Hide Hard and Easy off | More → Reviewer and Deck Options for audio/timers. Update one control at a time and confirm behavior on both sides, with auto-advance, and with Accessibility Dynamic Type. | [#29] · [#38] |
| Reviewer toolbar and controls | Top toolbar, Undo visible, other actions menu-only or hidden. Four tap zones, sensitivity 100%. Separate question and answer assignments | Reorder and toggle action visibility. Test four and nine zones, sensitivity, defaults and overrides for navigation, answer, ratings, flags, study actions and whiteboard. Check supported peripheral inputs. | [#29] · [#30] |
| Accessibility | Card, image, answer button and Browse text scale 100%. Minimum press 0 ms, double tap interval 200 ms | More → Accessibility / Reviewer. Check scaling at standard and Accessibility sizes, activate Show Answer with VoiceOver, and verify Reduce Motion with native and rendered card content. | [#25] · [#29] · [#38] |
| Backups | 30-minute minimum interval, 12 daily, 10 weekly, 9 monthly | More → Backups → Backup Retention. Save and reopen, then verify a manual backup and retention without touching the second profile. | [#15] |
| Advanced | Replace newlines with HTML and focus typed answer on. Template microphone, dangerous collection access and external app launches off | More → Advanced. Verify both text-storage modes, native focus on a typed-answer card and permission denial/opt-in behavior. | [#30] · [#38] |

## Platform differences awaiting owner review

| Android behavior | iOS behavior and acceptance decision to record | Owner |
| --- | --- | --- |
| Navigation drawer gesture and double Back exit | Native iPhone tabs and adaptive iPad sidebar use system navigation and app lifecycle. Verify equivalent reachability and selection through iOS navigation and interruption. | [#25] · [#27] · [#38] |
| Android card frame/box rendering, cutout controls and hardware-rendering override | iOS offers a native card frame and requests system bar visibility. iOS and WebKit own safe areas and compositing. Verify reviewer layout and content visibility on cutout devices. | [#29] · [#38] |
| Typed-answer keyboard mode and field keyboard-language hint | Typed answer uses the card's WebKit input on iOS. The device keyboard switcher selects the field keyboard, while the hint remains in collection data. Verify answer comparison and hint round trip. | [#7] · [#33] · [#38] |
| Android filesystem, in-app shared-deck download and permissive media-picker setting | iOS keeps live data in its sandbox, imports permitted content types via Files and downloads shared decks in the system browser. Decide whether arbitrary attachments need an iOS route. Verify the download handoff and storage visibility. | [#15] · [#32] · [#34] · [#38] |
| Android global text actions, ContentProvider and instant editor | iOS uses the user-initiated Share extension. It returns to the sender and queues work for the main app's matching profile. System-wide text-to-Browse and Android's third-party API need an owner decision. | [#37] · [#38] |
| Android notification channels, vibration and LED, and widget refresh | iOS owns notification delivery, Focus, authorization and WidgetKit refresh. Hayaki publishes the active profile's widget snapshot and precomputes available local reminders. Compare scheduled rules, delivered counts and routes under normal system settings. | [#37] |
| Android package/debug tools and reporting | iOS uses local logs, system crash diagnostics and an opt-in debug-only Web Inspector. Record the decision on Android's in-app stress generators, crash/lock/corruption tools and legacy path selector. Analytics and automatic crash reporting remain disabled. | [#38] |

## Device matrix to finish

- [ ] **iPhone and iPad navigation.** On iPhone portrait and landscape and iPad portrait, landscape and narrow multitasking width, visit all four sections, open and close the reviewer and detail panes, change size during study and return from Files. Verify exactly one reviewer, unchanged selection and actions reachable at compact widths and both orientations. Record shortcuts, sidebar and tab behavior.
- [ ] **Accessibility and appearance.** Walk every destination and major modal at default and largest Accessibility Dynamic Type sizes. On both device families, navigate with VoiceOver, study from question to rating and read chart data and count labels. Check touch targets, clipped content, label contrast and answer order in Light, Dark, Black and system-controlled appearance. Complete the actual app language and RTL relaunch checks with the long-title fixture.
- [ ] **Interruption and media.** Interrupt offline review, edit, import and sync with background/resume or process restart as applicable. Verify retained work, rollback or explicit retry and the intended profile. Check audio ordering and sound, recording, camera, Pencil, hardware keyboard and controller, and WebKit process recovery.
- [ ] **Transfer and signing.** Finish both package directions on actual devices from Files, including an already-present note and a preserved backup. Follow the clean-checkout install guide for the app-only and App Groups builds. Verify normal launch, share return, widget installation/configuration and delivered notification routes with the intended signing profile.
- [ ] **Hosted sync.** Record AnkiWeb collection and media results independently of the local-server checks.
- [ ] **Sign-off.** Add test or device results to the owning issues. Record decisions for each platform difference and confirm any remaining implementation gaps with the parent before closing acceptance. [#1] · [#25]

[product]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/PRODUCT.md
[gallery]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/README.md
[study-source]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/core-loop/old-study-screen-features.md
[round-trip]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/round-trip/README.md
[android-prefs]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/AnkiDroid/src/main/java/com/ichi2/anki/settings/Prefs.kt
[android-reminders]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/AnkiDroid/src/main/java/com/ichi2/anki/reviewreminders/AddEditReminderDialogViewModel.kt
[core-options]: https://github.com/ankitects/anki/tree/c06370ff4d87cb48d825f90cc83e02b9a4e84ecd/ts/routes/deck-options
[ci-first]: https://github.com/amemiya02/Hayaki-IOS/actions/runs/44530950322
[ci-retry]: https://github.com/amemiya02/Hayaki-IOS/actions/runs/44538876433
[c24]: https://github.com/amemiya02/Hayaki-IOS/commit/5260c16
[c37]: https://github.com/amemiya02/Hayaki-IOS/commit/65992e1
[c38]: https://github.com/amemiya02/Hayaki-IOS/commit/522fd2a
[01]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-01.webp
[02]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-02.webp
[03]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-03.webp
[04]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-04.webp
[05]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-05.webp
[06]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-06.webp
[07]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-07.webp
[08]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-08.webp
[09]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-09.webp
[10]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-10.webp
[11]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-11.webp
[12]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-12.webp
[13]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-13.webp
[14]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-14.webp
[15]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-15.webp
[16]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-16.webp
[17]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-17.webp
[18]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-18.webp
[19]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-19.webp
[20]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-20.webp
[21]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-21.webp
[22]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-22.webp
[23]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-23.webp
[24]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-24.webp
[25]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-25.webp
[26]: https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/en-walk-26.webp
[#1]: https://github.com/amemiya02/Hayaki-IOS/issues/1
[#7]: https://github.com/amemiya02/Hayaki-IOS/issues/7
[#8]: https://github.com/amemiya02/Hayaki-IOS/issues/8
[#11]: https://github.com/amemiya02/Hayaki-IOS/issues/11
[#15]: https://github.com/amemiya02/Hayaki-IOS/issues/15
[#17]: https://github.com/amemiya02/Hayaki-IOS/issues/17
[#19]: https://github.com/amemiya02/Hayaki-IOS/issues/19
[#21]: https://github.com/amemiya02/Hayaki-IOS/issues/21
[#23]: https://github.com/amemiya02/Hayaki-IOS/issues/23
[#24]: https://github.com/amemiya02/Hayaki-IOS/issues/24
[#25]: https://github.com/amemiya02/Hayaki-IOS/issues/25
[#26]: https://github.com/amemiya02/Hayaki-IOS/issues/26
[#27]: https://github.com/amemiya02/Hayaki-IOS/issues/27
[#28]: https://github.com/amemiya02/Hayaki-IOS/issues/28
[#29]: https://github.com/amemiya02/Hayaki-IOS/issues/29
[#30]: https://github.com/amemiya02/Hayaki-IOS/issues/30
[#31]: https://github.com/amemiya02/Hayaki-IOS/issues/31
[#32]: https://github.com/amemiya02/Hayaki-IOS/issues/32
[#33]: https://github.com/amemiya02/Hayaki-IOS/issues/33
[#34]: https://github.com/amemiya02/Hayaki-IOS/issues/34
[#35]: https://github.com/amemiya02/Hayaki-IOS/issues/35
[#36]: https://github.com/amemiya02/Hayaki-IOS/issues/36
[#37]: https://github.com/amemiya02/Hayaki-IOS/issues/37
[#38]: https://github.com/amemiya02/Hayaki-IOS/issues/38
[e7]: https://github.com/amemiya02/Hayaki-IOS/issues/7#issuecomment-6932936092
[e8]: https://github.com/amemiya02/Hayaki-IOS/issues/8#issuecomment-7011929540
[e11]: https://github.com/amemiya02/Hayaki-IOS/issues/11#issuecomment-7011284953
[e15]: https://github.com/amemiya02/Hayaki-IOS/issues/15#issuecomment-7009821688
[e17]: https://github.com/amemiya02/Hayaki-IOS/issues/17#issuecomment-7009668478
[e19]: https://github.com/amemiya02/Hayaki-IOS/issues/19#issuecomment-7011284934
[e21]: https://github.com/amemiya02/Hayaki-IOS/issues/21#issuecomment-7011284901
[e23]: https://github.com/amemiya02/Hayaki-IOS/issues/23#issuecomment-7009287584
[e26]: https://github.com/amemiya02/Hayaki-IOS/issues/26#issuecomment-7008377949
[e26-reverse]: https://github.com/amemiya02/Hayaki-IOS/issues/26#issuecomment-7012897446
[e27]: https://github.com/amemiya02/Hayaki-IOS/issues/27#issuecomment-7011285015
[e28]: https://github.com/amemiya02/Hayaki-IOS/issues/28#issuecomment-7011285562
[e29]: https://github.com/amemiya02/Hayaki-IOS/issues/29#issuecomment-7011285575
[e30]: https://github.com/amemiya02/Hayaki-IOS/issues/30#issuecomment-7011929448
[e31]: https://github.com/amemiya02/Hayaki-IOS/issues/31#issuecomment-7011285771
[e32]: https://github.com/amemiya02/Hayaki-IOS/issues/32#issuecomment-7011285550
[e33]: https://github.com/amemiya02/Hayaki-IOS/issues/33#issuecomment-7011286574
[e34]: https://github.com/amemiya02/Hayaki-IOS/issues/34#issuecomment-7011286392
[e35]: https://github.com/amemiya02/Hayaki-IOS/issues/35#issuecomment-7011286577
[e36]: https://github.com/amemiya02/Hayaki-IOS/issues/36#issuecomment-7009130384
[ci-follow-up]: https://github.com/amemiya02/Hayaki-IOS/actions/runs/44545812392
[c19]: https://github.com/amemiya02/Hayaki-IOS/commit/6d6ba8c
[c29]: https://github.com/amemiya02/Hayaki-IOS/commit/905ea36
