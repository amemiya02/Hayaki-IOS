# iOS implementation and acceptance tickets

[Parent issue #1](https://github.com/amemiya02/Hayaki-IOS/issues/1) tracks the [native iOS specification](hayaki-v1.md). Each sheet number below refers to the [pinned Android walkthrough](https://github.com/amemiya02/Hayaki/blob/0f5dc353fb424751d74ba7d315457b62d95348a7/docs/redesign/milestone-5/gallery/README.md). Check current code at that revision for behaviors added after the walkthrough. The entries below describe work to verify or finish.

Existing closed tickets supply reusable work. #2–#3 cover the core and bridge, #4 and #9 the shell and decks, #5 and #14 packages, #6 basic study, #10 note creation, #12–#13 browsing, #16 self-hosted collection sync, #18 basic options, #20 basic statistics and #22 daily reminders. Each remains valid for its original scope.

## Revised tickets

### [#7](https://github.com/amemiya02/Hayaki-IOS/issues/7) · Verify card rendering and playback on iOS

Sheets 03, 08–09. The implementation and Mac tests exist. Finish the outstanding simulator/device checks.

- Render offline image, audio, MathJax, cloze and typed-answer fixtures through the reviewer. Verify long-card scrolling, answer comparison, automatic audio order and manual replay.
- Compare template styling, night-mode classes and media output with the same cards on Android. Record screen evidence and an audible playback result.

### [#8](https://github.com/amemiya02/Hayaki-IOS/issues/8) · Complete reviewer actions and session outcomes

Sheets 03–04. Build on the basic study session in #6 and the core-backed actions in Browse.

- Exercise undo/redo, bury or suspend a card or note, mark, flag, edit, set due date and the other reviewer actions available at the pin. Compare queue, counts, card state and intervals after the action.
- Distinguish an empty queue, later learning, daily limits, buried cards and finished filtered decks. Show the corresponding next action or return time.
- Check the result after app relaunch and after returning from the editor. Keep the answer controls usable one-handed.

### [#11](https://github.com/amemiya02/Hayaki-IOS/issues/11) · Edit, preview and delete notes

Sheets 08–09. Extend the existing add-note flow from #10 through Browse and the reviewer.

- Edit fields, markup and tags, handle duplicates and empty fields, preview both card sides, and cancel or confirm deletion. Preserve untouched fields byte-for-byte.
- Verify the editor toolbar, sticky fields and repeated-entry behavior against Android. Return to the same browser selection or study session with the edited card refreshed. Dedicated multimedia and note-type tickets cover their tools.

### [#15](https://github.com/amemiya02/Hayaki-IOS/issues/15) · Protect, inspect and recover each collection

Sheets 18, 21–22. Exercise backup settings, manual and automatic backups, retention, integrity and media checks, storage management and recovery.

- Restore a selected backup after confirmation and a pre-restore backup. Reopen the collection and compare scheduling and history. Keep live data private and expose permitted backup files in Files.
- Check missing and unused media, failure to open a collection and the recovery path. Switching profiles must never restore or remove another profile's files.

### [#17](https://github.com/amemiya02/Hayaki-IOS/issues/17) · Sync media with the active profile and destination

Sheets 23–24 plus the later Android sync revision. Reuse the collection sync from #16.

- Test both transfer directions against a real self-hosted server, visible progress, failure, retry after interruption and explicit cancellation. Collection success and media failure have distinct states.
- Change destination or profile with work queued. Verify the previous credentials, files and retries never reach the new destination. Verify reopening the app restores an accurate status.

### [#19](https://github.com/amemiya02/Hayaki-IOS/issues/19) · Complete native deck options and FSRS

Sheet 05. #18 delivered presets and basic scheduling options. Inventory all controls and conditional sections at the Android pin, including FSRS, limits, easy days, timers, audio, auto-advance and custom scheduling where exposed.

- For each section, edit, save, reopen and compare stored values on Android. Verify shared presets and per-deck overrides and preserve unrelated fields.
- Exercise desired retention, parameter optimization, cancellation, insufficient history and the simulator when available. Compare outputs using the same collection and inputs.

### [#21](https://github.com/amemiya02/Hayaki-IOS/issues/21) · Complete native statistics and chart interactions

Sheet 02 and Android's statistics page. Extend #20's today, card counts and ratings.

- Inventory every graph, selector, interaction and empty state available at the pin. Include forecast, review counts and time, calendar, intervals, hourly breakdown, true retention and available FSRS distributions.
- Use the same deck, period, time zone and fixture history to compare totals and series across apps. Exercise the filters and expose chart values to VoiceOver in each appearance.

### [#23](https://github.com/amemiya02/Hayaki-IOS/issues/23) · Explain transfers, sync choices and project identity

Sheets 01 and 19–21. Put the guide, help, version, changelog and credits under More.

- Walk through Hayaki Android ↔ iOS and AnkiDroid/desktop package exchange. Say which import merges and which replaces, and link to the matching actions.
- Describe the sync destinations available in the running build and distinguish self-hosted setup from AnkiWeb. Verify the displayed source repository, app/core versions, license and credits.

### [#24](https://github.com/amemiya02/Hayaki-IOS/issues/24) · Cover interface languages and upstream translations

Across all sheets, check English, Simplified Chinese and Japanese for app-owned strings, notifications, extensions, core messages and errors.

- Select each first-class language, reopen the app, and compare terms and glyphs in menus, interval labels and the editor. Long deck names leave counts readable.
- Preserve applicable upstream localizations. Exercise the English fallback for a new string and check a right-to-left language through the core loop.

### [#25](https://github.com/amemiya02/Hayaki-IOS/issues/25) · Audit the complete iPhone and iPad feature inventory

Use sheets 01–26 and the pinned source. Maintain a checklist of each Android entry, setting, edge state, iOS equivalent, evidence and owning ticket. Include behavior added after the gallery and controls outside it.

- Walk the four destinations, split view, compact iPad window and both orientations. Check Dynamic Type, VoiceOver, contrast, touch targets, themes and interruption/resume cases.
- Validate the build and install guide from a clean checkout. Link outstanding discrepancies to the parent and attach test or device evidence before signing off the inventory.

### [#26](https://github.com/amemiya02/Hayaki-IOS/issues/26) · Verify package exchange on Android and iOS devices

Sheets 20–21 and the Android round-trip fixtures. Preserve the original AnkiDroid interoperability checks and add both Hayaki apps as first-class peers.

- Exchange a deck package and a whole collection in both directions between Hayaki Android and iOS. Compare notes, cards, fields, tags, scheduling, review history, deck options and media after merge or replacement.
- Repeat with the reference AnkiDroid install and retain the original authorized AnkiDroid→AnkiWeb check. Record app versions, fixtures and observed discrepancies. Local package exchange can be checked independently of hosted sync.

## New parity tickets

### [#27](https://github.com/amemiya02/Hayaki-IOS/issues/27) · Match Welcome, Decks and native navigation

Sheets 01–03. Reuse the native shell and deck management from #4 and #9.

- Offer Android's start-empty, import, shared-deck and available sync entry paths. Show today's due and studied counts and a direct study action. Verify nested deck actions and empty and finished states.
- Make Decks, Browse, Stats and More reachable through iPhone tabs and iPad sidebar/split view. Preserve the selected deck on return from study, imports and More.

### [#28](https://github.com/amemiya02/Hayaki-IOS/issues/28) · Build filtered decks and custom study

Sheets 04–05. Reproduce Android's custom-study choices and filtered-deck options using the core.

- Configure searches, secondary filters, limits, ordering and rescheduling. Build, preview, rebuild and empty a filtered deck.
- Check that cards return to their original deck with the expected scheduling for preview and rescheduling modes. Compare counts and completion messages on both platforms.

### [#29](https://github.com/amemiya02/Hayaki-IOS/issues/29) · Support reviewer inputs, speech, whiteboard and recordings

Sheets 06 and 15–17. Use the pinned study feature decisions to inventory supported actions and settings.

- Configure tap zones, gestures, hardware keys, controller commands, toolbar, timers and accessibility timings. Exercise commands on question and answer sides and verify saved bindings after restart.
- Test template speech, voice selection where supported, audio record/replay, draw/hide/save whiteboard, touch/Pencil input and per-deck state. Check the saved file and interruption or denied microphone permission.

### [#30](https://github.com/amemiya02/Hayaki-IOS/issues/30) · Port the supported card-template scripting interface

Use the Android study feature decisions and shipped template API at the pin. The card host is the boundary between a card and the native reviewer.

- Inventory the exported commands, side restrictions, permissions, responses and error behavior. Use fixture templates to cover read-only getters, reveal/rating, flags, speech and typed-answer focus.
- Exercise the same fixtures on Android and iOS in study and preview. Check session state, unavailable commands and recovery when the rendering process exits.

### [#31](https://github.com/amemiya02/Hayaki-IOS/issues/31) · Complete Browse, selection and card information

Sheets 05, 07–08 and 14. Extend the search, row paging and bulk actions from #12–#13.

- Compare the available card/note modes, saved searches, filters, columns, sort orders and selection actions using a common fixture. Exercise multi-selection across pages and a 100,000-card collection.
- Open native card info and verify scheduling and review history. Run applicable bulk actions, undo and return to the same query. Hand change-note-type requests to the mapping flow.

### [#32](https://github.com/amemiya02/Hayaki-IOS/issues/32) · Add multimedia editing and image occlusion

Sheets 09–11. Extend the existing image attachment and note editor.

- Record/replay audio, import media, draw, preview and crop an image. Verify cancellation, permissions, resulting field markup and local files after saving.
- Create, edit and delete image-occlusion masks through a native editor. Preview and review the generated cards, then export and check masking and media on Android.

### [#33](https://github.com/amemiya02/Hayaki-IOS/issues/33) · Manage note types, fields, templates and conversions

Sheets 12–14. Provide native note-type and field actions, template editing and change-note-type mappings.

- Edit fields, order, template sides, style and browser appearance. Render both preview sides against representative notes and check the resulting cards on Android.
- Change note type from Browse and the editor, map fields and templates, preview the effect and confirm any required one-way sync. Verify cancellation and preservation of mapped content and scheduling.

### [#34](https://github.com/amemiya02/Hayaki-IOS/issues/34) · Complete import, export and shared-deck flows

Sheets 20–22. Extend package support from #5 and #14. Inventory every Android importer, exporter and supported format in the pinned build.

- Import delimited text with encoding/delimiter, field mapping and duplicate choices as exposed. Check import summaries and cancellation. Discover a shared deck, download it and enter the same import flow.
- Verify legacy-compatible export, scheduling and media choices, Files and share-sheet entry, progress and recoverable failure. Check both merge and confirmed collection replacement.

### [#35](https://github.com/amemiya02/Hayaki-IOS/issues/35) · Isolate profiles and sync destinations

Sheets 18–19 and 23–24 plus the later Android sync change. Implement Android's profile operations, isolate collections, media, backups, credentials and pending work.

- Switch profiles during queued work, restart and verify isolation. Preserve existing self-hosted settings when upgrading and after a failed login or endpoint change.
- Exercise login, logout, incremental and forced sync, upload/download confirmations, wrong credentials and interruption against a local server. Once approved, test equivalent AnkiWeb flows and the new-profile default. Keep hosted credentials in the platform credential store.

### [#36](https://github.com/amemiya02/Hayaki-IOS/issues/36) · Obtain and verify AnkiWeb access for Hayaki iOS

The iOS client needs written permission covering its use of AnkiWeb. Android code and Kioku availability do not establish that permission.

- Record the owner's confirmation and a reference to the scope of the authorization. Keep private correspondence and credentials out of the issue.
- After authorization, verify actual iOS sign-in, collection and media sync, profile isolation and switching destinations. Until then keep the public endpoint disabled and report this parity gap separately.

### [#37](https://github.com/amemiya02/Hayaki-IOS/issues/37) · Add share-to-note, widgets and deck reminders

Sheets 11 and 24–26. Extend #22's existing daily reminder. Use the iOS share extension, WidgetKit and notifications.

- Share text from another app into quick add or the full editor, save or cancel, then return to the sender. Verify target deck/profile and card contents.
- Configure the Android widget equivalents (deck list and one deck), update counts after study and open the right destination. Configure deck-specific reminders and test notification delivery, denied permission and opening a reminder from a cold start.

### [#38](https://github.com/amemiya02/Hayaki-IOS/issues/38) · Complete appearance, preferences and accessibility settings

Sheets 15–19. Inventory every Android preference and default, including general, appearance, study, controls, accessibility, sync, backup, advanced and developer settings. Assign feature-specific behavior to its owning ticket.

- Implement native search/navigation and persistence for applicable settings. Document the iOS equivalent of any Android system setting or refer a genuine platform gap for owner decision.
- Verify system appearance and explicit Light, Dark and Black choices, semantic rating/count colors and language-correct type. Keep the card frame distinct from template-owned content. Verify privacy defaults against Android.
