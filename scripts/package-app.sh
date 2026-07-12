#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="BarFold"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/dist/$APP_NAME.app"

cd "$ROOT"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Support/Info.plist" "$APP_DIR/Contents/Info.plist"

SIGNING_IDENTITY="${BARFOLD_SIGNING_IDENTITY:-Apple Development: kevin80828@gmail.com (LMR6XPUZQ4)}"
if security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY"; then
    codesign --force --deep --options runtime --timestamp=none --sign "$SIGNING_IDENTITY" "$APP_DIR"
else
    echo "warning: stable signing identity not found; using ad-hoc signature" >&2
    codesign --force --deep --sign - "$APP_DIR"
fi
echo "$APP_DIR"
