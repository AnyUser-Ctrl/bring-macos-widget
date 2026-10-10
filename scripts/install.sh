#!/usr/bin/env bash
#
# Builds a Release of BringWidget, installs it to /Applications and starts it.
# Run it again to update an existing installation (login + list are kept).
#
# Requires: Xcode (selected via xcode-select), xcodegen (brew install xcodegen),
# an "Apple Development" certificate in the login keychain and
# Config/Team.xcconfig with your Team ID (see Config/Team.xcconfig.example).
#
# Usage:  ./scripts/install.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Build outside the repo: iCloud/File-Provider folders add extended
# attributes that codesign rejects.
BUILD_DIR="${TMPDIR:-/tmp}/bringwidget-build"
APP_PATH="$BUILD_DIR/Build/Products/Release/BringWidget.app"
TARGET="/Applications/BringWidget.app"

cd "$PROJECT_DIR"

if [[ ! -f Config/Team.xcconfig ]]; then
    echo "ERROR: Config/Team.xcconfig is missing." >&2
    echo "       cp Config/Team.xcconfig.example Config/Team.xcconfig" >&2
    echo "       and enter your Team ID (see docs/GUIDE.md, step 3)." >&2
    exit 1
fi

echo "==> Generating Xcode project..."
xcodegen generate >/dev/null

echo "==> Building Release (takes 1–2 minutes the first time)..."
if ! xcodebuild \
    -project BringWidget.xcodeproj \
    -scheme BringWidget \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -destination 'platform=macOS' \
    build > "$BUILD_DIR.log" 2>&1; then
    grep -E "error:" "$BUILD_DIR.log" | sort -u >&2 || true
    echo "ERROR: Build failed, full log: $BUILD_DIR.log" >&2
    exit 1
fi

echo "==> Installing to $TARGET..."
pkill -x BringWidget 2>/dev/null || true
if [[ -d "$TARGET" ]]; then
    rm -rf "$TARGET"
fi
ditto "$APP_PATH" "$TARGET"

echo "==> Starting BringWidget..."
open "$TARGET"

echo "==> Done. Now sign in in the app and add the widget:"
echo "    Right-click the desktop → \"Edit Widgets…\" → search for \"Bring\"."
