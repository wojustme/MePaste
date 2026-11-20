#!/bin/bash

set -euo pipefail

# An optimized (-c release) local build is still a development build, even if
# HEAD has a version tag. Only the GitHub tag workflow stamps a release version.
if [[ "${GITHUB_ACTIONS:-}" != "true" || "${GITHUB_REF_TYPE:-}" != "tag" ]]; then
    exit 0
fi

INFO_PLIST="${1:?Usage: release-version.sh <Info.plist>}"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
RELEASE_TAG="${GITHUB_REF_NAME:-}"

if [[ "$RELEASE_TAG" != "v$APP_VERSION" ]]; then
    echo "Release tag ($RELEASE_TAG) must match app version (v$APP_VERSION)." >&2
    exit 1
fi

printf '%s\n' "$RELEASE_TAG"
