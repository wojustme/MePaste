#!/bin/bash

set -euo pipefail

REPOSITORY="wojustme/MePaste"
TAP_REPOSITORY="wojustme/homebrew-tap"
VERSION=""
SHA256=""
TAP_DIRECTORY=""

usage() {
    cat <<'EOF'
Usage:
  ./scripts/update-homebrew-cask.sh --version <version> --sha256 <sha256> --tap-dir <path>

Generate the mepaste Homebrew cask in a checked-out wojustme/homebrew-tap repository.
The release asset must be available at:
  https://github.com/wojustme/MePaste/releases/download/v<version>/Paste-v<version>.dmg
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="${2:-}"
            shift 2
            ;;
        --sha256)
            SHA256="${2:-}"
            shift 2
            ;;
        --tap-dir)
            TAP_DIRECTORY="${2:-}"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$VERSION" || -z "$SHA256" || -z "$TAP_DIRECTORY" ]]; then
    echo "--version, --sha256, and --tap-dir are required." >&2
    usage >&2
    exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}([-.][0-9A-Za-z.]+)?$ ]]; then
    echo "Invalid version: $VERSION" >&2
    exit 1
fi

if [[ ! "$SHA256" =~ ^[a-fA-F0-9]{64}$ ]]; then
    echo "Invalid SHA-256 checksum." >&2
    exit 1
fi

if [[ ! -d "$TAP_DIRECTORY/.git" ]]; then
    echo "Tap directory is not a Git repository: $TAP_DIRECTORY" >&2
    exit 1
fi

ORIGIN_URL="$(git -C "$TAP_DIRECTORY" remote get-url origin)"
if [[ "$ORIGIN_URL" != *"$TAP_REPOSITORY"* ]]; then
    echo "Tap directory origin must point to $TAP_REPOSITORY, got: $ORIGIN_URL" >&2
    exit 1
fi

CASK_DIRECTORY="$TAP_DIRECTORY/Casks"
CASK_PATH="$CASK_DIRECTORY/mepaste.rb"
mkdir -p "$CASK_DIRECTORY"

cat > "$CASK_PATH" <<EOF
cask "mepaste" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$REPOSITORY/releases/download/v#{version}/Paste-v#{version}.dmg"
  name "Paste"
  desc "Native macOS clipboard history manager"
  homepage "https://github.com/$REPOSITORY"

  depends_on macos: ">= :ventura"

  app "Paste.app"
end
EOF

echo "Updated $CASK_PATH"
echo "Validate with: brew audit --cask --strict $CASK_PATH"
