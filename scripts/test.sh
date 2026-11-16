#!/usr/bin/env bash
# Runs every local package's tests on this Mac, against the macOS slice of the
# real core and throwaway collections (build the core first with
# scripts/build-core.sh).
#
#   scripts/test.sh                 # every package that has tests
#   scripts/test.sh DecksFeature    # only the named packages
#
# A new package under Packages/ with a Tests folder is picked up automatically.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/Packages"

if [[ $# -gt 0 ]]; then
    packages=("$@")
else
    packages=()
    for manifest in */Package.swift; do
        package="${manifest%/Package.swift}"
        [[ -d "$package/Tests" ]] && packages+=("$package")
    done
fi

failed=()
for package in "${packages[@]}"; do
    printf '\n==> Testing %s\n' "$package"
    swift test --package-path "$package" || failed+=("$package")
done

if [[ ${#failed[@]} -gt 0 ]]; then
    printf '\nerror: tests failed in: %s\n' "${failed[*]}" >&2
    exit 1
fi
printf '\nAll package tests passed: %s\n' "${packages[*]}"
