#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="$ROOT/Support/Info.plist"
OUTPUT_DIR="$ROOT/outputs"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")"
ARCHIVE="$OUTPUT_DIR/BarFold-$VERSION.zip"

"$ROOT/scripts/package-app.sh"

mkdir -p "$OUTPUT_DIR"
rm -f "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$ROOT/dist/BarFold.app" "$ARCHIVE"

codesign --verify --deep --strict --verbose=2 "$ROOT/dist/BarFold.app"
unzip -t "$ARCHIVE" >/dev/null
shasum -a 256 "$ARCHIVE"
echo "$ARCHIVE"
