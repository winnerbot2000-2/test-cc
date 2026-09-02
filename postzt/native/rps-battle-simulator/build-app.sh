#!/bin/bash
# Builds RPSBattleSimulator.app (release) and assembles the bundle with icon + Info.plist.
#
# Usage:
#   build-app.sh                 # assemble the .app next to this script (standalone RPS dev)
#   build-app.sh <dest-dir>      # assemble the .app into <dest-dir> (TryPost native build)
#
# The TryPost native build passes `extras` so the bundle lands where electron-builder's
# `extraFiles` picks it up and where `config/rps.php` resolves it at runtime.
set -euo pipefail

CALLER_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Resolve the destination without requiring it to already exist.
DEST_ARG="${1:-$SCRIPT_DIR}"
if [[ "$DEST_ARG" = /* ]]; then
    DEST="$DEST_ARG"
else
    DEST="$CALLER_DIR/$DEST_ARG"
fi

SRC_PNG="$SCRIPT_DIR/Assets/icon.png"
INFO_PLIST="$SCRIPT_DIR/Assets/Info.plist"
ICONSET="$SCRIPT_DIR/.build/AppIcon.iconset"
ICNS="$SCRIPT_DIR/.build/AppIcon.icns"
APP="$DEST/RPSBattleSimulator.app"

cd "$SCRIPT_DIR"

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
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/RPSBattleSimulator "$APP/Contents/MacOS/RPSBattleSimulator"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
cp "$INFO_PLIST" "$APP/Contents/Info.plist"

echo "==> Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP"

echo "==> Done: $APP"
