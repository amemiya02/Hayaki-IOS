# Embed upstream Anki's Rust core, pinned to one exact version

Scheduling, search, card rendering, sync and package import/export are not written in Swift. The app embeds upstream Anki's Rust core (`ankitects/anki`, starting at tag `26.09.4`, the version AnkiDroid ships) and calls it through a small C bridge, the same way AnkiDroid and AnkiMobile do. A Swift rewrite would take years and would drift from desktop Anki in ways that silently corrupt scheduling or break sync.

## Consequences

- The project is licensed AGPL-3.0-or-later, because the core is.
- The app is locked to one Anki version at a time. The core's protobuf interface is explicitly not a public API and its method numbering changes between versions, so everything generated from it is regenerated on each upgrade, and an upgrade is a deliberate, tested step.
- The core is built by script from a pinned submodule and is not committed, so building the app needs a Rust toolchain.
- The core is used unpatched. Earlier iOS projects patched it down to English only to save about 7 MB; we keep every translation because the app ships in Chinese and Japanese.
