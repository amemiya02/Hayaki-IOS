# Use Android Hayaki as the acceptance baseline for native iOS

Hayaki on iPhone and iPad will implement the learner-visible behavior of the [Android baseline](https://github.com/amemiya02/Hayaki/tree/0f5dc353fb424751d74ba7d315457b62d95348a7). Keep the unpatched Anki core, SwiftUI screens and the web view for card content and previews. The previous release limits on statistics, deck options and other features are superseded by the full Android inventory.

Self-hosted sync and AnkiWeb are both product requirements. Existing self-hosted profiles retain their destination and credentials. Enable AnkiWeb for this client only after written permission covering Hayaki iOS is recorded. Until then, test self-hosted sync independently and report the outstanding AnkiWeb gap. This supersedes the product scope in [ADR 0002](0002-no-ankiweb.md) and the subset in [ADR 0004](0004-all-native-screens.md).
