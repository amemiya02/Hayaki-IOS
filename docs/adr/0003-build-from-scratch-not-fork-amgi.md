# Build from scratch instead of forking Amgi

When this project started (November 2026) a free, AGPL-licensed iOS client built on Anki's Rust core already existed: Amgi (`antigluten/amgi`). We chose to write a new app instead of forking it, and to treat Amgi's bridge and build recipe as a reference to learn from and improve on, with credit, since both projects share a licence.

A fork would have inherited a working app, but also an iOS 18 baseline, an existing app structure, and a core patched down to English only. This project wants an iOS 26 baseline, Swift 6 strict concurrency throughout, an entirely native SwiftUI interface, and Chinese and Japanese from the first release, which is easier to reach from an empty repository than by reshaping someone else's.

## Consequences

Forking would not have helped with AnkiWeb access either; see [0002](0002-no-ankiweb.md).
