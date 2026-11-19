# Hayaki

The native iPhone and iPad edition of [Hayaki for Android](https://github.com/amemiya02/Hayaki). The feature port is in progress. Hayaki keeps the learner's whole collection on the device, works offline, and reads and writes the same collection that desktop Anki and AnkiDroid do, because it embeds the same Anki core they use: upstream Anki's Rust core, pinned to Anki 26.09.4.

Hayaki is built from source and installed on the simulator or on your own device; it is not distributed through the App Store. Sync with AnkiWeb or a self-hosted Anki sync server through the upstream Anki core. [Sync decision](docs/adr/0005-android-parity.md)

## Not affiliated with Anki

Hayaki is an independent project. It is not affiliated with, endorsed by or supported by Ankitects Pty Ltd, the makers of Anki and AnkiWeb, nor by the AnkiDroid project. "Anki" is used only to say which collections Hayaki works with. Please do not report Hayaki problems to the Anki or AnkiDroid projects.

## Building

Prerequisites: a Mac with Apple silicon, Xcode 27, [rustup](https://rustup.rs), `protoc` and XcodeGen (`brew install protobuf xcodegen`). The Rust version (1.97.1) and the iOS and macOS targets are pinned in `core/rust-toolchain.toml` and installed by rustup automatically.

```sh
git clone --branch hayaki-v1 https://github.com/amemiya02/Hayaki-IOS.git
cd Hayaki-IOS
scripts/build-core.sh     # builds Anki's core for iOS, the simulator and macOS (long the first time)
scripts/test.sh           # runs package tests on the Mac against the real core
xcodegen generate         # writes Hayaki.xcodeproj from project.yml
open Hayaki.xcodeproj     # then run the Hayaki scheme on a simulator
```

To include the local sync-server integration tests, run `scripts/build-sync-server.sh` before `scripts/test.sh`.

To build and run in the simulator from the command line, choose a device listed by `xcrun simctl list devices available` and use that name throughout this example:

```sh
xcodebuild build -project Hayaki.xcodeproj -scheme Hayaki \
    -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData \
    CODE_SIGNING_ALLOWED=NO
xcrun simctl boot 'iPhone 17' # skip this command if the device is already booted
open -a Simulator
xcrun simctl install 'iPhone 17' build/DerivedData/Build/Products/Debug-iphonesimulator/Hayaki.app
xcrun simctl launch 'iPhone 17' io.github.amemiya02.hayaki
```

`Hayaki.xcodeproj` is generated and ignored by git: change `project.yml`, never the project. Details of the core build, its decisions and the upgrade procedure: [docs/building-the-core.md](docs/building-the-core.md). Every push is built and tested by GitHub Actions (`.github/workflows/ci.yml`).

### Installing on your own device

Build the core first. For a provisioning profile without App Groups, including an Xcode Personal Team using a free Apple Account, generate the app-only configuration with `xcodegen generate --spec project-personal.yml`. It includes local reminders. In Xcode, sign in to your Apple Account, select your team under **Hayaki → Signing & Capabilities**, select your connected iPhone or iPad as the Hayaki scheme's run destination, and click Run. With a Personal Team, the provisioning profile expires after seven days. Run again from Xcode to rebuild and reinstall. [Apple's Personal Team provisioning](https://developer.apple.com/help/account/basics/about-your-developer-account#enable-a-personal-team-in-xcode)

For an installation with Share and widgets, generate the default configuration with `xcodegen generate` and use a team that can provision App Groups. Register `group.io.github.amemiya02.hayaki` and assign it to the App IDs for `io.github.amemiya02.hayaki`, `io.github.amemiya02.hayaki.share`, and `io.github.amemiya02.hayaki.widgets`. In the generated project, select that team for **Hayaki**, **HayakiShare**, and **HayakiWidgets** under Signing & Capabilities. Run the Hayaki scheme on your connected device. [Apple’s App Groups setup](https://developer.apple.com/documentation/xcode/configuring-app-groups) · [iOS provisioning capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-ios)

Both configurations generate `Hayaki.xcodeproj`. Reapply your signing team in Xcode after regenerating the project.

## How the code is organised

The app target (`App/`) is only an entry point. Everything else is a local Swift package under `Packages/`:

- `AnkiCore`: the Core Client, Hayaki's only way into Anki's core.
- `CollectionStore`: where the collection lives; opening, closing and replacing it; the change signal; undo. Its `CollectionTesting` library gives tests a throwaway collection.
- `AppShell`: opens the collection at launch and shows the sections, as tabs on iPhone and a sidebar on iPad.
- One package per feature: `DecksFeature`, `BrowseFeature`, `StatisticsFeature`, `SettingsFeature`, and more as they are built. Conventions for adding to them: [docs/feature-packages.md](docs/feature-packages.md).

Tests drive feature models against the real core and a throwaway collection on the Mac; the core is never mocked. The full specification is in [docs/specs/hayaki-v1.md](docs/specs/hayaki-v1.md); vocabulary in [GLOSSARY.md](GLOSSARY.md); decisions in [docs/adr/](docs/adr/).

## Licence and credits

Hayaki is licensed under the GNU Affero General Public License, version 3 or (at your option) any later version (AGPL-3.0-or-later), because Anki's core is. The licence text is in [LICENSE](LICENSE).

Hayaki stands on the work of others:

- [Anki](https://github.com/ankitects/anki) by Ankitects and its contributors: the Rust core Hayaki embeds, unmodified, with its translations.
- [AnkiDroid](https://github.com/ankidroid/Anki-Android) and its [backend](https://github.com/ankidroid/Anki-Android-Backend): the model for driving Anki's core from a mobile app and testing against the real core.
- [Amgi](https://github.com/antigluten/amgi): an earlier iOS client whose bridge and build recipe Hayaki learned from.

Third-party code shipped in the app:

- [MathJax](https://www.mathjax.org) 3.2.2 by the MathJax Consortium, licensed under the Apache License 2.0: draws the maths on cards. The prebuilt files come unmodified from the `mathjax` package on npm (the version upstream Anki bundles); `scripts/update-mathjax.sh` fetches them and checks their checksum. They and MathJax's licence are in `Packages/StudyFeature/Sources/StudyFeature/WebAssets/mathjax/`.
- The card host page's typed-answer and replay-button styles and its MathJax settings follow Anki's reviewer (AGPL-3.0-or-later, Ankitects Pty Ltd and contributors).
