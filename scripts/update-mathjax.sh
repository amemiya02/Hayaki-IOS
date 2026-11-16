#!/bin/sh
# Fetches the prebuilt MathJax that the study screen's card web view uses for
# cards with maths, and copies the files Hayaki ships into
# Packages/StudyFeature/Sources/StudyFeature/WebAssets/mathjax.
#
# The version is the one upstream Anki 26.09.4 bundles (its yarn.lock pins
# mathjax 3.2.2), from the npm registry, checked against the registry's
# published SHA-512. Only what upstream's reviewer loads is copied: the
# combined TeX-to-CommonHTML component, its web fonts and the assistive
# MathML extension (for VoiceOver), plus MathJax's licence (Apache-2.0).
#
# Usage: scripts/update-mathjax.sh   (from the repository root)
set -eu

VERSION=3.2.2
SHA512=06df9249553c7811b6ef30a155ec0e89c62ced7b1db78d2a9b8f94a47c97ee4d3f3bd36588f73ec7bee4d7f144b0fb2328f64626fb5164cd6f3be81e5b43a11b
DEST=Packages/StudyFeature/Sources/StudyFeature/WebAssets/mathjax

[ -d Packages/StudyFeature ] || { echo "Run from the repository root." >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

curl -sSfL -o "$WORK/mathjax.tgz" "https://registry.npmjs.org/mathjax/-/mathjax-$VERSION.tgz"
echo "$SHA512  $WORK/mathjax.tgz" | shasum -a 512 -c -
mkdir "$WORK/x"
tar -xzf "$WORK/mathjax.tgz" -C "$WORK/x"
SRC="$WORK/x/package"

rm -rf "$DEST"
mkdir -p "$DEST/output/chtml/fonts/woff-v2" "$DEST/a11y"
cp "$SRC/LICENSE" "$DEST/LICENSE"
cp "$SRC/es5/tex-chtml-full.js" "$DEST/tex-chtml-full.js"
cp "$SRC/es5/a11y/assistive-mml.js" "$DEST/a11y/assistive-mml.js"
cp "$SRC"/es5/output/chtml/fonts/woff-v2/*.woff "$DEST/output/chtml/fonts/woff-v2/"
echo "MathJax $VERSION copied to $DEST"
