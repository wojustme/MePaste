#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")}"
DMG_SOURCE="$BUILD_DIR/MePaste.dmg"
RELEASE_DIR="$BUILD_DIR/release"
DMG_NAME="MePaste-v${VERSION}.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"
CHECKSUM_PATH="$RELEASE_DIR/${DMG_NAME}.sha256"

"$ROOT_DIR/scripts/build-dmg.sh"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
cp "$DMG_SOURCE" "$DMG_PATH"

(
    cd "$RELEASE_DIR"
    shasum -a 256 "$DMG_NAME" > "$(basename "$CHECKSUM_PATH")"
)

echo "Prepared release asset: $DMG_PATH"
echo "SHA-256: $(cut -d ' ' -f 1 "$CHECKSUM_PATH")"
