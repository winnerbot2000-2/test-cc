#!/bin/bash
# Builds RPSBattleSimulator.app (release) and assembles the bundle with icon + Info.plist.
set -euo pipefail
cd "$(dirname "$0")"

SRC_PNG="Assets/icon.png"
INFO_PLIST="Assets/Info.plist"
ICONSET=".build/AppIcon.iconset"
ICNS=".build/AppIcon.icns"
APP="RPSBattleSimulator.app"

echo "==> Building release binary..."
swift build -c release

echo "==> Generating AppIcon.icns from $SRC_PNG..."
rm -rf "$ICONSET" "$ICNS"
mkdir -p "$ICONSET"
sips -z 16   16   "$SRC_PNG" --out "$ICONSET/icon_16x16.png"       >/dev/null
sips -z 32   32   "$SRC_PNG" --out "$ICONSET/icon_16x16@2x.png"    >/dev/null
sips -z 32   32   "$SRC_PNG" --out "$ICONSET/icon_32x32.png"       >/dev/null
sips -z 64   64   "$SRC_PNG" --out "$ICONSET/icon_32x32@2x.png"    >/dev/null
sips -z 128  128  "$SRC_PNG" --out "$ICONSET/icon_128x128.png"     >/dev/null
sips -z 256  256  "$SRC_PNG" --out "$ICONSET/icon_128x128@2x.png"  >/dev/null
sips -z 256  256  "$SRC_PNG" --out "$ICONSET/icon_256x256.png"     >/dev/null
sips -z 512  512  "$SRC_PNG" --out "$ICONSET/icon_256x256@2x.png"  >/dev/null
sips -z 512  512  "$SRC_PNG" --out "$ICONSET/icon_512x512.png"     >/dev/null
sips -z 1024 1024 "$SRC_PNG" --out "$ICONSET/icon_512x512@2x.png"  >/dev/null
iconutil -c icns "$ICONSET" -o "$ICNS"

echo "==> Assembling $APP..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/RPSBattleSimulator "$APP/Contents/MacOS/RPSBattleSimulator"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
cp "$INFO_PLIST" "$APP/Contents/Info.plist"

echo "==> Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP"

echo "==> Done: $APP"
