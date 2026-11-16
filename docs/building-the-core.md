# Building the Anki core

Hayaki embeds upstream Anki's Rust core (ADR 0001). The core is built from source by one command and is never committed.

## Prerequisites

- A Mac with Apple silicon and Xcode 27 or newer (with its command line tools).
- [rustup](https://rustup.rs). The Rust version is pinned in `core/rust-toolchain.toml` (1.97.1, the version upstream Anki 26.09.4 pins). rustup installs it, and the targets `aarch64-apple-ios`, `aarch64-apple-ios-sim` and `aarch64-apple-darwin`, automatically on the first build. To install them by hand:

  ```sh
  rustup toolchain install 1.97.1 --profile minimal \
      --target aarch64-apple-ios --target aarch64-apple-ios-sim --target aarch64-apple-darwin
  ```

- The protobuf compiler, `protoc`, version 3.15 or newer: `brew install protobuf`. Set `PROTOC` to use a different binary.
- Network access on the first build, to fetch the Anki submodule, Rust crates and Apple's swift-protobuf package.

Nothing else is needed: the build does not use Python, Node or Anki's own build system. The Swift protobuf code generator is built from the swift-protobuf version that `Packages/AnkiCore` pins, so it always matches the runtime library.

## Build

From the repository root:

```sh
scripts/build-core.sh
```

The first run takes a long time (the core is compiled once per target); later runs are incremental. The script:

1. checks out `vendor/anki` at the pinned tag `26.09.4` and its two translation submodules (`ftl/core-repo`, `ftl/qt-repo`);
2. builds the bridge crate `core/bridge`, which links the unpatched core, for iOS devices, the iOS simulator on Apple silicon and macOS on Apple silicon;
3. packages the three slices as `Packages/AnkiCore/Frameworks/HayakiBridge.xcframework`;
4. generates the service and method numbers (`Packages/AnkiCore/Sources/AnkiCore/Generated/CoreMethods.swift`) from the core's own descriptor set, and the Swift message types (`Packages/AnkiCore/Sources/AnkiProto/Generated/`) from the core's `.proto` files.

All outputs are ignored by git. Intermediate files go to `build/core/`.

## Test

```sh
swift test --package-path Packages/AnkiCore
```

The tests run on the Mac against the macOS slice of the real core, using a throwaway collection in a temporary folder.

## How the bridge works

`core/bridge` is a small Rust crate with four C functions, declared in `core/bridge/include/HayakiBridge.h`: open a backend, run a method by service and method number, free a returned buffer, close a backend. Every entry point catches panics, so a panic in the core comes back as an `anki.backend.BackendError` of kind `ANKIDROID_PANIC_ERROR` instead of aborting the app. The release profile keeps `panic = "unwind"` for this reason.

Upstream Anki is used as path dependencies and is not patched. `core/Cargo.lock` was seeded from upstream's lock file, so the core builds with the exact dependency versions upstream tested. All of the core's translations, and the desktop translations the core includes by default, are compiled in.

## Decisions and known pitfalls

- **Dynamic framework, not a static library.** The bridge is a `cdylib` packaged as `HayakiBridge.framework`. A static library interfered with SwiftUI previews in an earlier iOS client (Amgi), and would also require every Swift target that links it to repeat the core's system library and framework dependencies; the dynamic library resolves those itself when it is linked. The cost is one embedded framework in the app, which Xcode embeds and signs automatically from the binary target.
- **Install name set at link time.** Each slice is linked with `-install_name @rpath/HayakiBridge.framework/...` (the versioned path on macOS), so the binary is never rewritten afterwards and the linker's code signature stays valid.
- **No stripping.** Stripping the dylib has corrupted its LINKEDIT segment in Amgi's build; the release profile sets `strip = false`, and the script never runs `strip`.
- **Descriptor path passed explicitly.** The core's build scripts look for the descriptor set at `OUT_DIR/../../anki_descriptors.bin` unless `DESCRIPTORS_BIN` is set, and newer cargo build-directory layouts break that fallback. The script sets `DESCRIPTORS_BIN=build/core/descriptors.bin`; the code generator reads the same file, so the generated numbers always match the built library.
- **Numbers are generated, never written by hand.** Service and method numbers come from upstream's `anki_proto_gen::get_services`, the same helper the core's dispatcher is generated from. They change between Anki versions, so upgrading the core means moving the submodule and re-running the script.

## Upgrading the core

1. Check out the new tag in `vendor/anki` and commit the submodule change.
2. Update `channel` in `core/rust-toolchain.toml` to match `vendor/anki/rust-toolchain.toml`.
3. Refresh `core/Cargo.lock` from upstream: copy `vendor/anki/Cargo.lock` over it and run `cargo metadata --manifest-path core/Cargo.toml > /dev/null`.
4. Run `scripts/build-core.sh` and the tests.

Credit: the overall recipe (a small bridge crate around `run_service_method`, packaged as an XCFramework) follows AnkiDroid's backend and the Amgi project.
