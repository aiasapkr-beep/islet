#!/bin/bash
# Builds MediaRemoteAdapter.framework with clang only (no CMake).
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$SRC/build}"
FW="$OUT/MediaRemoteAdapter.framework"
rm -rf "$FW"; mkdir -p "$FW/Versions/A/Headers" "$FW/Versions/A/Resources"
SOURCES=$(find "$SRC/src/adapter" "$SRC/src/private" "$SRC/src/utility" -name '*.m')
clang -dynamiclib -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 \
  -fobjc-arc -fvisibility=default -O2 \
  -I"$SRC/include" -I"$SRC/src" \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name "@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter" \
  -o "$FW/Versions/A/MediaRemoteAdapter" $SOURCES
cp "$SRC/include/MediaRemoteAdapter.h" "$FW/Versions/A/Headers/"
cat > "$FW/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
<key>CFBundleName</key><string>MediaRemoteAdapter</string>
<key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>0.1.0</string>
</dict></plist>
PLIST
ln -s A "$FW/Versions/Current"
ln -s Versions/Current/MediaRemoteAdapter "$FW/MediaRemoteAdapter"
ln -s Versions/Current/Headers "$FW/Headers"
ln -s Versions/Current/Resources "$FW/Resources"
codesign --force --deep --sign - "$FW" 2>/dev/null
echo "Built $FW"
