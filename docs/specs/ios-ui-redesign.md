# iOS UI/UX redesign

Status: agreed design, not yet implemented. Decided in a design review on 2026-11-20. [ADR 0006](../adr/0006-ios-native-visual-design.md) records the rule behind it: Android parity covers what a learner can do, while the look follows iOS.

Current-state screenshots: [`docs/assets/ui-audit-2026-11/`](../assets/ui-audit-2026-11/).

## Problems this fixes

- **Android or web look.** `HayakiTheme` uses Material 3's default palette (`#6750A4` purple on `#FEF7FF`). The study screen's top bar is a hand-built `ZStack`, and its icon toolbar is a horizontal `ScrollView`. Neither uses the system navigation bar.
- **iOS 26 design APIs are almost unused.** The whole codebase has 3 uses of Liquid Glass, `symbolEffect`, `sensoryFeedback`, `navigationSubtitle` and `fontDesign`. The stack itself is current (iOS 26 minimum, Swift 6, SwiftUI, Swift Charts) and stays.
- **The finished screen** is a `ContentUnavailableView` with up to five stacked `.bordered` buttons and several paragraphs of text.
- **Add Note** is a permanent `tabViewBottomAccessory` bar above the tab bar on every tab, for a rare action.
- **Titles are inconsistent.** Browse uses an inline title, while the other tabs use large titles. Decks has six toolbar items, which push its large title down a row.
- **Sync progress**, including media sync, is plain rows of text.
- **Only three appearances**: light, dark and black.

## Principles

1. **System first.** Use system semantic colors, materials, navigation bars, toolbars, lists, menus and sheets. A custom control is only allowed where no system control does the job.
2. **Liquid Glass for floating controls.** Use it for floating controls only (rating bar, toolbar buttons, bottom accessory). Content surfaces stay opaque system backgrounds.
3. **Brand only through the theme.** The accent color and a faint background tint are the only brand surfaces. No custom fonts and no illustrations.
4. **Colors that carry meaning never change with the theme.** Ratings and card counts keep the same colors in every theme.
5. **One rule set for every tab** (see Navigation).
6. **Rare actions live in menus. The frequent action gets the prominent spot.**
7. **Every change works with:** Dynamic Type up to AX5, VoiceOver, Increase Contrast, Reduce Motion, Reduce Transparency, and RTL-safe layout.

## Tokens

### Color

| Role | Value |
|---|---|
| Screen background | `Color(.systemGroupedBackground)` for lists, `Color(.systemBackground)` for the study screen, plus the theme tint |
| Card or section surface | `Color(.secondarySystemGroupedBackground)` |
| Text | `.primary`, `.secondary`, `.tertiary` |
| Accent | The theme accent (see Themes) |
| Again / Hard / Good / Easy | `.red` / `.orange` / `.green` / `.blue` (system colors, never themed) |
| New / Learning / Due counts | `.blue` / `.red` / `.green` (Anki's meanings, never themed) |

The theme tint is the accent at 4% opacity over the background in light mode and 6% in dark mode. Black mode gets no tint, so the background stays pure black.

### Typography

- **System fonts only, with Dynamic Type.** Use `.system` with a text style, and never name a font. iOS then picks PingFang SC/TC/HK or Hiragino Sans for Chinese and Japanese text based on the UI language.
- **SF Rounded and `monospacedDigit()` are for text that is only digits.** This covers card counts, rating intervals, finished-screen figures, statistics headline numbers and deck row counts. SF Rounded has no Chinese or Japanese glyphs, so put a number and its unit in separate `Text` views (`Text(12)` next to `Text("cards")`). Otherwise Rounded digits sit next to square CJK text.
- **Card default font.** `CardHost.html` sets `font-family: -apple-system, system-ui;` and keeps `line-height: 1.75`. A font family set in a card template still wins. When that font has no CJK glyphs (Arial, for example), the system falls back by `lang` (see Study screen).

### Spacing, shape and motion

- **Spacing scale:** 4, 8, 12, 16, 20, 24, 32. The page margin is the system's (`.contentMargins` or list default).
- **Shapes:**
  - Surfaces: `.rect(cornerRadius: 20, style: .continuous)`.
  - Shapes nested in a surface: `ConcentricRectangle` (iOS 26), so their radii match the container.
  - Pills: `Capsule`.
- **Motion:**
  - Use SwiftUI default springs.
  - `symbolEffect` for state changes.
  - `sensoryFeedback` for ratings and for finishing a session.
  - With Reduce Motion on, every transition becomes a plain cross-fade or an instant change.

## Themes

The current single "appearance" setting becomes two independent settings in More → Appearance:

- **Appearance:** System, Light, Dark or Black. The existing "dark or black at night when following the system" choice stays.
- **Theme:** sets the accent color and the background tint. Paper and Midnight also set the study screen and card canvas. Each theme has tuned values for light and dark mode, and black mode reuses the dark accent.

Any theme can be combined with any appearance mode. The settings screen shows each theme as a small preview card.

| Theme | 中文 / 日本語 | Accent (light) | Accent (dark) | Canvas override |
|---|---|---|---|---|
| Hayaki (default) | 速 / 速 | `#2C776E` | `#7ED6CA` | none |
| Sakura | 樱 / 桜 | `#B04663` | `#FF9DB7` | none |
| Matcha | 抹茶 / 抹茶 | `#50743F` | `#A8CF8E` | none |
| Ocean | 海 / 海 | `#0A6E9E` | `#5EC4F0` | none |
| Indigo | 靛 / 藍 | `#3A5BD9` | `#8FA8FF` | none |
| Wisteria | 藤 / 藤 | `#745AB9` | `#B9A3F5` | none |
| Amber | 琥珀 / 琥珀 | `#916019` | `#F5C451` | none |
| Sumi | 墨 / 墨 | `#4A4A4F` | `#C7C7CC` | none |
| Paper | 纸 / 和紙 | `#8A5A2B` | `#D9A86C` | `#F6F1E7` light, `#1E1A15` dark |
| Midnight | 夜空 / 夜空 | `#1A757F` | `#5EE6EE` | `#EEF3FA` light, `#0B1426` dark |

- **Contrast:** every accent must reach 4.5:1 against its background for text-on-background use (checked by `HayakiAppearanceTests`). The light accents of Sakura, Matcha, Wisteria, Amber and Midnight were darkened from their first values to reach it; Paper and Midnight are also checked against their canvas. Black mode keeps a pure black canvas in every theme.
- **Adding a theme** means adding one entry of tokens, with no structural code change.
- **Widgets** follow the selected theme accent.
- **Hayaki** is the default. Its teal comes from the app icon's background, so the icon and the app read as one brand. The light accent is `#2C776E`, darkened slightly from the icon's `#2E7D74` so it reaches 4.5:1 on the tinted grouped background.

## Navigation rules (all tabs)

- **Titles:** Every tab root uses a large title (`.navigationBarTitleDisplayMode(.automatic)`), Browse included. Search uses the system default placement for the tab.
- **Pushed screens and sheets use inline titles** (`.navigationBarTitleDisplayMode(.inline)`), so the title sits on the same row as the system back button or the sheet's Cancel and Done, as in iOS Settings. This covers every screen under More, Deck Options, Card Info, Note Types and the rest.
- **Leading side:** nothing, except an Edit-style mode toggle where a screen has one.
- **Trailing side:** at most one trailing group of primary actions plus one `ellipsis` menu, combined with `ToolbarItemGroup` so they share one glass capsule (Decks' Sync and `+` share one glass group). Everything else goes in the menu.
- **Sheets:** use `presentationDetents`. A sheet's Cancel or Close goes on the leading side and Done or Save on the trailing side.
- **Tab bar:** Decks, Browse, Stats and More, unchanged. iPad keeps the sidebar.

| Screen | Trailing items | Menu contents |
|---|---|---|
| Decks | Sync, `+` (Add Note), `⋯` | Import, Export, Shared Decks, Import Text, Export Text, Create Deck |
| Browse | `+` (Add Note), `⋯` | Columns, Filters, Saved Searches, Select |
| Stats | `⋯` | Deck or search selection, Export PDF |
| More | none | none |

- **More and Stats:** the audit found no item at the top left; what reads as misalignment is an empty toolbar band above More's large title, and on Stats the scroll-edge blur of content behind the inline title. Both disappear once every tab shares the same toolbar treatment and background.

## Add Note entry points

Remove the permanent bottom accessory. Add Note can be reached from:

- the `+` in Decks and Browse
- the study screen's `⋯` menu
- Command-N
- a Home Screen quick action and an App Shortcut (`AppShortcutsProvider`), so it works from Spotlight and Siri
- the existing Share extension

## Sync

- **Bottom accessory.** The tab view's bottom accessory, freed by moving Add Note, appears only while a sync is running. It is a glass strip showing:
  - a circular progress indicator
  - a status line, for example «正在同步媒体 · 已检查 120 · 新增 8»
  - a cancel button

  When the sync succeeds, the strip shows a checkmark (`symbolEffect(.bounce)`) for about 2 seconds and then hides. When it fails, the strip stays and shows the reason with a Retry button. On iPad, the strip sits at the foot of the sidebar. iOS 26.0 cannot hide the bottom accessory, so there the same strip floats as glass at the bottom of each tab's content (`safeAreaInset`) instead.
- **Sync button in Decks.** It rotates while syncing (`symbolEffect(.rotate)`) and shows a badge dot when there are local changes. A conflict needing a full upload or download still uses the existing confirmation dialog.
- **More → Sync screen.** Collection status and media status become two labeled rows. Each row has a status icon (synced, syncing, failed or interrupted), the last sync time as relative text, and an inline progress bar while running. Failure details go in a row under the status row, with Retry as a row button.

## Study screen

### Top: system navigation bar

- **Navigation bar.** The study screen sits in a `NavigationStack` with a glass toolbar:
  - Leading: Close (`xmark`).
  - Title: a custom `.title` toolbar item with the deck name over the counts, for example `12 · 3 · 40`, in blue, red and green, using SF Rounded and `monospacedDigit`. The time left and the answer timer appear under the name when they are turned on. (`navigationSubtitle` cannot keep a color per number, so the counts are not a system subtitle.)
  - Trailing: Undo, then the `⋯` menu with all other reviewer actions.
- **Toolbar setting.** It has two choices: "Buttons in bar" or "Menu only". The current top/bottom/hidden setting maps to these when the setting is migrated, and the Bottom option is removed.
- **Progress.** When turned on, a thin progress line sits on the bottom edge of the navigation bar.
- **Flags.** A flagged card tints the `⋯` icon with the flag color, as it does today.

### Bottom: answer bar

- **Layout.** The bar floats above the card in a `GlassEffectContainer`:
  - **Question side:** one full-width "Show Answer" button with `.buttonStyle(.glassProminent)`, in the same position the rating buttons will take.
  - **Answer side:** four `.glass` buttons tinted with the rating colors. Each shows the interval in small SF Rounded text above the rating name. With hide Hard/Easy turned on, there are two buttons. At accessibility text sizes, the buttons form a 2×2 grid.
- **Feedback.** Each rating gives `sensoryFeedback(.impact)`: lighter for Easy and Good, firmer for Again. The existing minimum-press and cooldown behavior stays.
- **Card reveal.** The answer fades in, with no 3D flip, and there is no animation when Reduce Motion is on.

### Card content

- **Glyph setting.** A new global setting, Study → **Card Kanji/Hanzi Style** («卡片汉字字形» / «カードの漢字字形»), has four options:
  - Follow App Language (default)
  - 日本語
  - 简体中文
  - 繁體中文

  It sets `<html lang>` on `CardHost.html`, which makes WebKit choose Hiragino Sans or PingFang for Han characters. This setting is global for now; a per-deck version would need extra data in the deck config.
- **iPad width.** On iPad the card content has a maximum readable width and is centered.

## Finished screen

This replaces the stacked buttons. From top to bottom, it shows:

1. **Header.** A large SF Symbol with an entrance animation (`symbolEffect(.bounce)`) and a single success haptic. Use `checkmark.seal.fill` in green for All Done and `clock.fill` in secondary for limit, learning-later or buried. Below the symbol, one title line such as «今日学习已完成».
2. **Session card.** A rounded surface with the cards reviewed and the time spent as large SF Rounded figures, plus a small Swift Charts bar showing the rating breakdown (Again / Hard / Good / Easy).
3. **Next events.** One `Label` row each, with an icon: «下一张学习卡 14:20», «新的学习日 明天 04:00». These replace the paragraphs of text.
4. **Actions.** An inset-grouped list with icon rows, shown only when they apply: Custom Study, Deck Options, Unbury Cards, Rebuild Filtered Deck.
5. **Done.** One `.glassProminent` Done button pinned to the bottom, also the default keyboard action.

## Decks screen

- **Summary card.** A "Today" card at the top shows total new, learning and due cards, with a Study All button, plus "Study Now · <deck>" for the current deck and a line with what was studied today. The core studies one deck tree per session, so Study All runs each top-level deck with cards due, in list order, and continues to the next one automatically when a deck finishes.
- **Deck rows:**
  - The deck name on the left.
  - Count pills on the right, in SF Rounded and the count colors, hiding any count of 0.
  - Tapping the row starts study. Long press opens the context menu, and swiping shows Rename and Delete, as today.
  - Subdecks keep disclosure.
- **Empty state.** A `ContentUnavailableView` with Import and Shared Decks actions.

## Statistics screen

- **Period.** A segmented picker at the top: 1 month, 3 months, 1 year, all.
- **Scope.** The chosen deck or search shows as the navigation subtitle.
- **Today card.** Reviews today, time, correct rate and current streak, as large SF Rounded numbers.
- **Graph cards.** Each graph is its own rounded card: a title, a one-line plain-language reading (for example «未来 7 天平均每天 85 张»), and the chart. All charts:
  - support finger scrubbing with `chartXSelection` and a value callout
  - scroll horizontally where long, such as Forecast and Review History (`chartScrollableAxes`)
  - use system colors, with the rating and count meanings from Tokens
- **Calendar heat map.** Built with Swift Charts `RectangleMark`.
- **iPad.** The cards form a two-column grid.

## Browse screen

- **Title and search.** Large title with system search placement (see Navigation rules).
- **Toolbar.** Trailing `+` and `⋯`.
- **Rows.** Sort field as the primary text, deck and due date as secondary text. The flag is a colored leading bar, and suspended cards are dimmed.
- **iPad.** Two columns: the list, and a preview or editor beside it.

## Other screens and polish

These are smaller follow-on passes under the same rules:

- **Settings (More):**
  - Group rows the way iOS Settings does, with colored rounded-square icons.
  - Profiles stays the top row.
  - Search stays.
- **Note editor:**
  - Field labels as section headers.
  - The formatting toolbar as a keyboard accessory in a glass capsule.
  - The note type and deck pickers as menu rows.
- **Deck options:** keep the native form, and use rounded number readouts for limits and steps.
- **Welcome screen:** the mascot app icon as the brand mark (not an illustration), a large title, a short value line, and two glass buttons, Import or Sync. Text Import, Shared Decks and Start Empty stay as secondary links.
- **Loading:** `redacted(reason: .placeholder)` placeholders on lists and charts instead of a lone spinner.
- **Errors:** inline banner rows instead of alerts wherever the user can keep working.
- **App icon:** light, dark and tinted variants ship in the asset catalog. The Clear mode needs an Icon Composer icon and is tracked in #59.
- **Keyboard (iPad and hardware keyboards):** every shortcut appears in the system shortcut overlay.

## Acceptance

- No use of the Material palette remains, and all colors come from system semantic colors or theme tokens.
- Every tab root follows the navigation rules: large title, nothing on the leading side, and at most one trailing group of primary actions plus one `⋯` menu.
- All ten themes work in light, dark and black, and every accent passes the contrast check.
- The study and finished screens match this spec at default text size and at AX5, in Chinese, Japanese and English, on iPhone and iPad.
- UI tests keep their existing accessibility identifiers, or are updated in the same change.
- Before and after screenshots are added next to the audit set.
