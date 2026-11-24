#!/bin/zsh
# Builds a universal (Apple Silicon + Intel) Screent.app and packs it into
# releases/<version>/Screent-<version>.zip with a SHA-256 checksum.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
OUT="releases/$VERSION"

./scripts/build-app.sh --universal

mkdir -p "$OUT"
ZIP="$OUT/Screent-$VERSION.zip"
rm -f "$ZIP"
# ditto keeps the bundle structure and code signature intact
ditto -c -k --sequesterRsrc --keepParent build/Screent.app "$ZIP"
(cd "$OUT" && shasum -a 256 "Screent-$VERSION.zip" > "Screent-$VERSION.zip.sha256")

echo "Release: $ZIP"
lipo -archs build/Screent.app/Contents/MacOS/Screent
cat "$OUT/Screent-$VERSION.zip.sha256"
