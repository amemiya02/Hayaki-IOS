#!/usr/bin/env bash
# Builds Anki's Rust core behind Hayaki's bridge and packages it for Swift.
#
#   scripts/build-core.sh
#
# Produces (all ignored by git):
#   Packages/AnkiCore/Frameworks/HayakiBridge.xcframework
#       slices: iOS devices, iOS simulator (Apple silicon), macOS (Apple silicon)
#   Packages/AnkiCore/Sources/AnkiProto/Generated/*.pb.swift
#       Swift message types from the core's protobuf definitions
#   Packages/AnkiCore/Sources/AnkiCore/Generated/CoreMethods.swift, CoreCalls.swift
#       service and method numbers and a typed Swift call for every method,
#       from the core's own descriptor set
#
# Prerequisites and the reasons behind the choices are in docs/building-the-core.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE="$ROOT/Packages/AnkiCore"
BUILD="$ROOT/build/core"
FRAMEWORK_NAME="HayakiBridge"
IOS_MIN="26.0"
MACOS_MIN="26.0"
TARGETS=(aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-darwin)

step() { printf '\n==> %s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

step "Checking prerequisites"
command -v rustup >/dev/null || fail "rustup not found; install it from https://rustup.rs"
command -v xcodebuild >/dev/null || fail "Xcode not found"
PROTOC="${PROTOC:-$(command -v protoc || true)}"
[[ -x "$PROTOC" ]] || fail "protoc not found; install it with: brew install protobuf"
"$PROTOC" --version >/dev/null || fail "$PROTOC does not run; try: brew reinstall protobuf"
export PROTOC

step "Fetching the pinned Anki core and its translations"
# Shallow: only the pinned commit is needed, not Anki's whole history.
git -C "$ROOT" submodule update --init --depth 1 vendor/anki
git -C "$ROOT/vendor/anki" submodule update --init --depth 1 ftl/core-repo ftl/qt-repo

# rustup reads core/rust-toolchain.toml and installs the pinned Rust version and
# the three targets if they are missing.
cd "$ROOT/core"
rustc --version

export DESCRIPTORS_BIN="$BUILD/descriptors.bin"
export CARGO_TARGET_DIR="$BUILD/cargo"
export IPHONEOS_DEPLOYMENT_TARGET="$IOS_MIN"
export MACOSX_DEPLOYMENT_TARGET="$MACOS_MIN"
# Keep the builder's absolute paths out of the library (panic locations and
# debug strings): the checkout becomes "hayaki/" and Cargo's home "cargo/".
CARGO_HOME_DIR="${CARGO_HOME:-$HOME/.cargo}"
export RUSTFLAGS="${RUSTFLAGS:-} --remap-path-prefix=$ROOT=hayaki --remap-path-prefix=$CARGO_HOME_DIR=cargo"
export CFLAGS="${CFLAGS:-} -ffile-prefix-map=$ROOT=hayaki -ffile-prefix-map=$CARGO_HOME_DIR=cargo"

FRAMEWORKS="$BUILD/frameworks"
rm -rf "$FRAMEWORKS"
mkdir -p "$FRAMEWORKS"

modulemap() {
    cat <<EOF
framework module $FRAMEWORK_NAME {
    umbrella header "$FRAMEWORK_NAME.h"
    export *
}
EOF
}

info_plist() { # $1 = platform name, $2 = minimum OS key line
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>$FRAMEWORK_NAME</string>
    <key>CFBundleIdentifier</key><string>io.github.amemiya02.hayaki.bridge</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$FRAMEWORK_NAME</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleSupportedPlatforms</key><array><string>$1</string></array>
    $2
</dict>
</plist>
EOF
}

for target in "${TARGETS[@]}"; do
    if [[ "$target" == *darwin ]]; then
        # macOS frameworks use the versioned bundle layout.
        install_name="@rpath/$FRAMEWORK_NAME.framework/Versions/A/$FRAMEWORK_NAME"
    else
        install_name="@rpath/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME"
    fi

    step "Building the core for $target"
    # The install name is set at link time so the linker's code signature stays
    # valid (no install_name_tool afterwards), and the binary is never stripped.
    cargo rustc --locked --release --package hayaki_bridge --target "$target" \
        --crate-type cdylib -- -C "link-arg=-Wl,-install_name,$install_name"

    dylib="$CARGO_TARGET_DIR/$target/release/libhayaki_bridge.dylib"
    fw="$FRAMEWORKS/$target/$FRAMEWORK_NAME.framework"
    case "$target" in
        aarch64-apple-ios)
            platform="iPhoneOS"; min_os="<key>MinimumOSVersion</key><string>$IOS_MIN</string>" ;;
        aarch64-apple-ios-sim)
            platform="iPhoneSimulator"; min_os="<key>MinimumOSVersion</key><string>$IOS_MIN</string>" ;;
        aarch64-apple-darwin)
            platform="MacOSX"; min_os="<key>LSMinimumSystemVersion</key><string>$MACOS_MIN</string>" ;;
    esac

    if [[ "$target" == *darwin ]]; then
        contents="$fw/Versions/A"
        mkdir -p "$contents/Headers" "$contents/Modules" "$contents/Resources"
        cp "$dylib" "$contents/$FRAMEWORK_NAME"
        cp "$ROOT/core/bridge/include/$FRAMEWORK_NAME.h" "$contents/Headers/"
        modulemap > "$contents/Modules/module.modulemap"
        info_plist "$platform" "$min_os" > "$contents/Resources/Info.plist"
        ln -s A "$fw/Versions/Current"
        for item in "$FRAMEWORK_NAME" Headers Modules Resources; do
            ln -s "Versions/Current/$item" "$fw/$item"
        done
    else
        mkdir -p "$fw/Headers" "$fw/Modules"
        cp "$dylib" "$fw/$FRAMEWORK_NAME"
        cp "$ROOT/core/bridge/include/$FRAMEWORK_NAME.h" "$fw/Headers/"
        modulemap > "$fw/Modules/module.modulemap"
        info_plist "$platform" "$min_os" > "$fw/Info.plist"
    fi
done

step "Packaging $FRAMEWORK_NAME.xcframework"
XCFRAMEWORK="$PACKAGE/Frameworks/$FRAMEWORK_NAME.xcframework"
rm -rf "$XCFRAMEWORK"
mkdir -p "$PACKAGE/Frameworks"
xcframework_args=()
for target in "${TARGETS[@]}"; do
    xcframework_args+=(-framework "$FRAMEWORKS/$target/$FRAMEWORK_NAME.framework")
done
xcodebuild -create-xcframework "${xcframework_args[@]}" -output "$XCFRAMEWORK"

step "Generating the typed Swift calls"
cargo run --locked --release --quiet --package hayaki_codegen -- \
    "$DESCRIPTORS_BIN" "$PACKAGE/Sources/AnkiCore/Generated"

step "Generating Swift message types"
# protoc-gen-swift is built from the same swift-protobuf version the package
# resolves, so generated code and runtime library always match.
swift build --package-path "$PACKAGE" -c release --product protoc-gen-swift
PLUGIN="$(swift build --package-path "$PACKAGE" -c release --show-bin-path)/protoc-gen-swift"
PROTO_OUT="$PACKAGE/Sources/AnkiProto/Generated"
rm -rf "$PROTO_OUT"
mkdir -p "$PROTO_OUT"
"$PROTOC" --plugin="protoc-gen-swift=$PLUGIN" \
    --swift_out="$PROTO_OUT" --swift_opt=Visibility=Public \
    --proto_path="$ROOT/vendor/anki/proto" \
    "$ROOT"/vendor/anki/proto/anki/*.proto

step "Done"
echo "Built $XCFRAMEWORK"
echo "Run the tests with: swift test --package-path Packages/AnkiCore"
