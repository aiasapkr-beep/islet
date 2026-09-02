#!/bin/bash
# Builds NotchUsage.app into ./build (release, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/NotchUsage.app"

swift build -c "$CONFIG" 2>&1 | tail -n 3
BIN=".build/$CONFIG/NotchUsage"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchUsage"
cp Resources/Info.plist "$APP/Contents/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

# Ad-hoc signature so Keychain access is tied to a stable identity for this build.
codesign --force --deep --sign - "$APP"
echo "Built $APP"
