#!/usr/bin/env bash
# Builds blitzbot and assembles the .app bundle in ~/Downloads/blitzbot-build/
# — NEVER into the project directory (avoids Nextcloud syncing heavy build artifacts).
#
# Usage:
#   ./build-app.sh                       # ad-hoc sign
#   ./build-app.sh --sign <identity>     # e.g. blitzbot-dev (permissions survive rebuilds)

set -euo pipefail

IDENTITY="-"
if [[ "${1:-}" == "--sign" && -n "${2:-}" ]]; then
    IDENTITY="$2"
fi

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_ROOT="$HOME/Downloads/blitzbot-build"
SWIFT_BUILD="$BUILD_ROOT/swift"
APP_DIR="$BUILD_ROOT/blitzbot.app"

echo "→ build root: $BUILD_ROOT"
mkdir -p "$BUILD_ROOT"

echo "→ swift build -c release (scratch: $SWIFT_BUILD)"
cd "$PROJECT_DIR"
swift build -c release --scratch-path "$SWIFT_BUILD"

echo "→ assemble bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp -R "$PROJECT_DIR/blitzbot.app/Contents/Info.plist" "$APP_DIR/Contents/"
cp -R "$PROJECT_DIR/blitzbot.app/Contents/Resources" "$APP_DIR/Contents/"
cp "$SWIFT_BUILD/release/blitzbot" "$APP_DIR/Contents/MacOS/blitzbot"

echo "→ codesign (identity: $IDENTITY)"
codesign --force --deep --sign "$IDENTITY" "$APP_DIR"

echo "→ verify"
codesign -dv "$APP_DIR" 2>&1 | head -5

echo ""
echo "✔ blitzbot.app built at: $APP_DIR"
echo "  launch: open \"$APP_DIR\""
