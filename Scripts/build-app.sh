#!/bin/bash
# Builds Islet.app into ./build (release, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Islet.app"

swift build -c "$CONFIG" 2>&1 | tail -n 3
BIN=".build/$CONFIG/Islet"

# Now Playing helper (see Vendor/mediaremote-adapter/README.md). Built once, reused.
ADAPTER=Vendor/mediaremote-adapter
if [ ! -d "$ADAPTER/build/MediaRemoteAdapter.framework" ]; then
  "$ADAPTER/build-framework.sh" "$ADAPTER/build" 2>&1 | grep -vE "warning:|note:|^\s" || true
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Islet"
cp Resources/Info.plist "$APP/Contents/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp "$ADAPTER/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"
cp -R "$ADAPTER/build/MediaRemoteAdapter.framework" "$APP/Contents/Resources/"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

# Signing: use $ISLET_SIGN_IDENTITY, else a local "Islet Dev" certificate if one exists,
# else ad-hoc. A stable identity keeps the Keychain "Always Allow" grant across rebuilds
# (ad-hoc signatures change every build, so macOS asks again each time).
IDENTITY="${ISLET_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -q '"Islet Dev"'; then
  IDENTITY="Islet Dev"
fi
codesign --force --deep --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"
