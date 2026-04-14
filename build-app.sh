#!/usr/bin/env bash
# Builds blitzbot and assembles the .app bundle.
# Usage: ./build-app.sh [--sign <identity>]
#   default is ad-hoc signing (every rebuild = TCC permissions reset)
#   for stable permissions create a self-signed cert in Keychain Access and pass it via --sign blitzbot-dev

set -euo pipefail

IDENTITY="-"
if [[ "${1:-}" == "--sign" && -n "${2:-}" ]]; then
    IDENTITY="$2"
fi

echo "→ swift build -c release"
swift build -c release

echo "→ copy binary into bundle"
mkdir -p blitzbot.app/Contents/MacOS
cp .build/release/blitzbot blitzbot.app/Contents/MacOS/blitzbot

echo "→ codesign (identity: $IDENTITY)"
codesign --force --deep --sign "$IDENTITY" blitzbot.app

echo "→ verify"
codesign -dv blitzbot.app 2>&1 | head -5

echo ""
echo "✔ blitzbot.app ready. Launch via: open blitzbot.app"
