#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_PATH="$BUILD_DIR/MePaste.app"
DMG_PATH="$BUILD_DIR/MePaste.dmg"
STAGING_DIR="$BUILD_DIR/dmg"

# Always rebuild so an existing local/release bundle cannot leak the wrong
# commit or release version into this disk image. SwiftPM builds incrementally.
"$ROOT_DIR/scripts/build-app.sh"

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

cp -R "$APP_PATH" "$STAGING_DIR/MePaste.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "MePaste" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "Built $DMG_PATH"
shasum -a 256 "$DMG_PATH"
