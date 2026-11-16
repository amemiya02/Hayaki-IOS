#!/usr/bin/env bash
# Builds upstream Anki's self-hosted sync server from the pinned core source, for
# Hayaki's sync tests only. Hayaki itself never contains or starts a server.
#
#   scripts/build-sync-server.sh
#
# Produces (ignored by git):
#   build/sync-server/anki-sync-server
#
# The SyncFeature tests start this binary on a free local port with a throwaway
# data folder, and are skipped with a message when it has not been built. The
# server is upstream's `anki-sync-server` crate (vendor/anki/rslib/sync), built
# with upstream's own workspace and lock file, so it speaks exactly the sync
# protocol of the core Hayaki embeds. It is configured by environment variables:
# SYNC_USER1=user:password, SYNC_BASE=<data folder>, SYNC_HOST, SYNC_PORT.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/sync-server"

step() { printf '\n==> %s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

step "Checking prerequisites"
command -v rustup >/dev/null || fail "rustup not found; install it from https://rustup.rs"
PROTOC="${PROTOC:-$(command -v protoc || true)}"
[[ -x "$PROTOC" ]] || fail "protoc not found; install it with: brew install protobuf"
"$PROTOC" --version >/dev/null || fail "$PROTOC does not run; try: brew reinstall protobuf"
export PROTOC

step "Fetching the pinned Anki source and its translations"
git -C "$ROOT" submodule update --init --depth 1 vendor/anki
git -C "$ROOT/vendor/anki" submodule update --init --depth 1 ftl/core-repo ftl/qt-repo

# rustup reads vendor/anki/rust-toolchain.toml, the Rust version upstream pins.
cd "$ROOT/vendor/anki"
rustc --version

mkdir -p "$BUILD"
export CARGO_TARGET_DIR="$BUILD/cargo"
# See docs/building-the-core.md: newer cargo build-directory layouts break the
# core's fallback location for the descriptor set.
export DESCRIPTORS_BIN="$BUILD/descriptors.bin"

step "Building anki-sync-server"
cargo build --locked --release --package anki-sync-server

cp "$CARGO_TARGET_DIR/release/anki-sync-server" "$BUILD/anki-sync-server"

step "Done"
echo "Built $BUILD/anki-sync-server"
echo "Run the sync tests with: scripts/test.sh SyncFeature"
