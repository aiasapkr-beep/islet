#!/bin/bash
# Builds NotchUsage.app into ./build (release, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/NotchUsage.app"

swift build -c "$CONFIG" 2>&1 | tail -n 3
BIN=".build/$CONFIG/NotchUsage"

# Now Playing helper (see Vendor/mediaremote-adapter/README.md). Built once, reused.
ADAPTER=Vendor/mediaremote-adapter
if [ ! -d "$ADAPTER/build/MediaRemoteAdapter.framework" ]; then
  "$ADAPTER/build-framework.sh" "$ADAPTER/build" 2>&1 | grep -vE "warning:|note:|^\s" || true
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchUsage"
cp Resources/Info.plist "$APP/Contents/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp "$ADAPTER/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"
cp -R "$ADAPTER/build/MediaRemoteAdapter.framework" "$APP/Contents/Resources/"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

# Ad-hoc signature so Keychain access is tied to a stable identity for this build.
codesign --force --deep --sign - "$APP"
echo "Built $APP"
