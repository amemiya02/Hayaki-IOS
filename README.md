# Hayaki

A free, open-source, standalone client for Anki collections on iPhone and iPad. Hayaki is not affiliated with or endorsed by Anki's makers. It embeds upstream Anki's Rust core, pinned to Anki 26.09.4.

## Building

Prerequisites: a Mac with Apple silicon, Xcode 27, [rustup](https://rustup.rs) and `protoc` (`brew install protobuf`). The Rust version (1.97.1) and the iOS and macOS targets are pinned in `core/rust-toolchain.toml` and installed by rustup automatically.

```sh
git clone https://github.com/amemiya02/Hayaki.git
cd Hayaki
scripts/build-core.sh                      # builds Anki's core for iOS, the simulator and macOS
swift test --package-path Packages/AnkiCore
```

Details, decisions and the upgrade procedure: [docs/building-the-core.md](docs/building-the-core.md).

## Licence

AGPL-3.0-or-later, because Anki's core is. Credits: upstream [Anki](https://github.com/ankitects/anki), [AnkiDroid](https://github.com/ankidroid/Anki-Android-Backend) and [Amgi](https://github.com/antigluten/amgi).
