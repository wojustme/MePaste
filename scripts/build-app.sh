#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/Paste.app"
CONTENTS_DIR="$APP_DIR/Contents"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.png"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"

cd "$ROOT_DIR"
swift build -c release --arch arm64 --arch x86_64

if [[ ! -f "$ICON_SOURCE" ]]; then
    swift "$ROOT_DIR/scripts/generate-icon.swift" "$ICON_SOURCE"
fi

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$BUILD_DIR/AppIcon.icns"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp ".build/apple/Products/Release/Paste" "$CONTENTS_DIR/MacOS/Paste"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BUILD_DIR/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
rm -rf "$ICONSET_DIR"

codesign --force --deep --sign - "$APP_DIR"
ARCHITECTURES="$(lipo -archs "$CONTENTS_DIR/MacOS/Paste")"
if [[ "$ARCHITECTURES" != *"arm64"* || "$ARCHITECTURES" != *"x86_64"* ]]; then
    echo "Universal binary validation failed: $ARCHITECTURES" >&2
    exit 1
fi
echo "Built $APP_DIR"
echo "Architectures: $ARCHITECTURES"
