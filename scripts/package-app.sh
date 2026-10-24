#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="BarFold"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/dist/$APP_NAME.app"

cd "$ROOT"
swift build -c release -Xswiftc -warnings-as-errors

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Support/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT/Support/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$ROOT/LICENSE" "$APP_DIR/Contents/Resources/LICENSE"
for localization in "$ROOT"/Support/*.lproj; do
    [[ -d "$localization" ]] || continue
    cp -R "$localization" "$APP_DIR/Contents/Resources/"
done

SIGNING_IDENTITY="${BARFOLD_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning | awk -F '"' '/Apple Development:/ { print $2; exit }')"
fi

if [[ -n "$SIGNING_IDENTITY" ]] && security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY"; then
    # Developer ID builds use the hardened runtime and a secure timestamp so
    # the resulting bundle can be submitted to Apple's notarization service.
    if [[ "$SIGNING_IDENTITY" == Developer\ ID\ Application:* ]]; then
        codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_DIR"
    else
        codesign --force --deep --options runtime --timestamp=none --sign "$SIGNING_IDENTITY" "$APP_DIR"
    fi
else
    echo "warning: signing identity not found; using ad-hoc signature" >&2
    codesign --force --deep --sign - "$APP_DIR"
fi
echo "$APP_DIR"
