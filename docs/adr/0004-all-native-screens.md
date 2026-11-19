> [ADR 0005](0005-android-parity.md) retains native screens and supersedes the first-release limits on graphs and deck options.

# Every screen is native; no upstream Anki web pages

AnkiDroid does not build its own deck options, statistics, card info or import screens: it shows upstream Anki's web pages inside a web view, which gives it those screens complete and already translated. We build every screen natively in SwiftUI instead, including deck options and statistics (with Swift Charts), because the goal is an app that looks and behaves like a modern iOS app throughout. A web view is used only to draw the cards themselves, which is unavoidable because card templates are HTML.

## Consequences

- Deck options and statistics are our own work and can fall behind upstream. On every upgrade of the embedded core, both screens are re-checked against what upstream added or changed.
- The first release covers a chosen subset of deck options and seven of upstream's graphs, not all of them.
- The build needs no Node toolchain and the app carries none of upstream's web pages. The only web assets shipped are a small card host page of our own and a prebuilt MathJax, for cards that contain maths.
