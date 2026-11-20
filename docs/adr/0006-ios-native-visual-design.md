# Android parity covers behavior, not visual design

[ADR 0005](0005-android-parity.md) makes Android Hayaki the acceptance baseline for what a learner can do. That baseline covers features and behavior only: every Android capability must exist and be reachable on iOS, but colors, layout, typography, control placement and entry points follow iOS 26 conventions (system semantic colors, Liquid Glass, standard navigation and toolbars) and may differ freely from Android's Material 3 design. We chose this because a literal port of the Material palette and Android layouts made the app feel like a web page or an Android app on iPhone.

## Consequences

- The Material 3 palette in `HayakiTheme` is replaced, not tuned.
- A parity review checks that an Android feature exists and can be found on iOS, not that it looks or sits the same.
