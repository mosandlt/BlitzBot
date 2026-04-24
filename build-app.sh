#!/usr/bin/env bash
# blitzbot build & bundle.
#
# Modes:
#   ./build-app.sh                       # default: sign with local blitzbot-dev cert
#                                        # (TCC permissions + keychain ACL survive rebuilds)
#   ./build-app.sh --sign <identity>     # custom signing identity from your keychain
#   ./build-app.sh --release             # ad-hoc sign + zip for GitHub release
#                                        # (portable: any macOS user can run it, but will hit
#                                         Gatekeeper on first launch; see README "First launch")
#
# Output: ~/Downloads/blitzbot-build/blitzbot.app
# Never builds into the project directory (Nextcloud sync would choke on .build/).

set -euo pipefail

MODE="dev"
IDENTITY="blitzbot-dev"

if [[ "${1:-}" == "--release" ]]; then
    MODE="release"
    IDENTITY="-"
elif [[ "${1:-}" == "--sign" && -n "${2:-}" ]]; then
    IDENTITY="$2"
fi

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_ROOT="$HOME/Downloads/blitzbot-build"
SWIFT_BUILD="$BUILD_ROOT/swift"
APP_DIR="$BUILD_ROOT/blitzbot.app"

echo "→ mode: $MODE, signing identity: $IDENTITY"
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

# SPM ships per-target resource bundles next to the binary. They must live
# inside the .app or Bundle.module traps with _assertionFailure at runtime
# (e.g. KeyboardShortcuts.Recorder in Settings → Hotkeys).
for bundle in "$SWIFT_BUILD/release/"*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done

# macOS 26+ requires CFBundleIdentifier in resource bundles or Bundle(url:) returns nil,
# causing Bundle.module assertionFailure at runtime. SPM only writes CFBundleDevelopmentRegion,
# so we patch each copied bundle that is missing a bundle identifier.
for bundle in "$APP_DIR/Contents/Resources/"*.bundle; do
    [ -e "$bundle" ] || continue
    plist="$bundle/Info.plist"
    if [ -f "$plist" ] && ! /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" &>/dev/null; then
        bundle_name="$(basename "$bundle" .bundle)"
        /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string de.blitzbot.resource.$bundle_name" "$plist"
        /usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string BNDL" "$plist"
        /usr/libexec/PlistBuddy -c "Add :CFBundleName string $bundle_name" "$plist"
        /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$plist"
        /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.0" "$plist"
    fi
done

echo "→ codesign (identity: $IDENTITY)"
codesign --force --deep --sign "$IDENTITY" "$APP_DIR"

echo "→ verify"
codesign -dv "$APP_DIR" 2>&1 | head -6

if [[ "$MODE" == "release" ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_DIR/Contents/Info.plist")
    ZIP_PATH="$BUILD_ROOT/blitzbot-${VERSION}-macos-arm64.zip"
    rm -f "$ZIP_PATH"
    ( cd "$BUILD_ROOT" && ditto -c -k --keepParent blitzbot.app "$ZIP_PATH" )
    echo ""
    echo "✔ Release artifact: $ZIP_PATH"
    echo "   size: $(ls -lh "$ZIP_PATH" | awk '{print $5}')"
    echo "   signing: ad-hoc (end users must right-click → Open on first launch)"
else
    echo ""
    echo "✔ blitzbot.app built at: $APP_DIR"
    echo "  launch: open \"$APP_DIR\""
fi
