#!/usr/bin/env bash
#
# Builds a Release of BringWidget and packages it both as a portable .zip
# (transferable, smallest) and a polished .dmg (drag-to-Applications
# installer). Output lands in ./dist/.
#
# Requires: xcodegen (brew install xcodegen), Xcode with the project's
# DEVELOPMENT_TEAM signing identity, ditto + hdiutil (ship with macOS).
#
# Usage:  ./scripts/package.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="/tmp/bringwidget-build"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="BringWidget.app"

echo "==> Cleaning previous build..."
rm -rf "$BUILD_DIR"

echo "==> Regenerating Xcode project from project.yml..."
cd "$PROJECT_DIR"
xcodegen generate >/dev/null

echo "==> Building Release configuration..."
xcodebuild \
    -project BringWidget.xcodeproj \
    -scheme BringWidget \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -destination 'platform=macOS' \
    build 2>&1 | grep -E "error:|BUILD" | tail -3

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME"
if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: Build artifact not found at $APP_PATH" >&2
    exit 1
fi

mkdir -p "$DIST_DIR"

# --- ZIP (portable, smallest) ----------------------------------------------
echo "==> Packaging $DIST_DIR/BringWidget.app.zip..."
rm -f "$DIST_DIR/BringWidget.app.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$DIST_DIR/BringWidget.app.zip"

# --- DMG (drag-to-Applications installer) ----------------------------------
echo "==> Packaging $DIST_DIR/BringWidget.dmg..."
DMG_STAGING=$(mktemp -d)
trap 'rm -rf "$DMG_STAGING"' EXIT
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
rm -f "$DIST_DIR/BringWidget.dmg"
hdiutil create \
    -volname "Bring Widget" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DIST_DIR/BringWidget.dmg" >/dev/null

# --- Done ------------------------------------------------------------------
echo "==> Done."
ls -lh "$DIST_DIR"/BringWidget*
