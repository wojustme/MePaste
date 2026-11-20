#!/bin/bash

set -euo pipefail

ROOT_DIR="${1:?Usage: generate-build-version.sh <source-root> <output-directory>}"
OUTPUT_DIR="${2:?Usage: generate-build-version.sh <source-root> <output-directory>}"
COMMIT_ID="$(git -C "$ROOT_DIR" rev-parse --short=7 HEAD 2>/dev/null || printf 'unknown')"
OUTPUT_FILE="$OUTPUT_DIR/GeneratedBuildVersion.swift"

mkdir -p "$OUTPUT_DIR"
TEMP_FILE="$(mktemp "$OUTPUT_DIR/.build-version.XXXXXX")"
trap 'rm -f "$TEMP_FILE"' EXIT

cat > "$TEMP_FILE" <<EOF
// Generated at build time. Do not edit.
enum GeneratedBuildVersion {
    static let commitID = "$COMMIT_ID"
}
EOF

# Avoid recompiling the app when only this prebuild command runs again.
if ! cmp -s "$TEMP_FILE" "$OUTPUT_FILE"; then
    mv "$TEMP_FILE" "$OUTPUT_FILE"
fi
