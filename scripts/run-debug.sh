#!/usr/bin/env bash
# Build a Debug ClaudeStats.app to a dedicated DerivedData path and launch it.
#
# Why not `open -a Claude\ Stats` or the default DerivedData path: this is a
# menu-bar (LSUIElement) app. Multiple registered .app bundles with the same
# bundle id cause Launch Services conflicts and the menu-bar item silently
# fails to appear. Always build to /tmp/claude-stats-build and launch by full
# path so there is exactly one known bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED=/tmp/claude-stats-build
APP="$DERIVED/Build/Products/Debug/Claude Stats.app"

bash scripts/generate.sh

# Kill any running instance so the rebuild can replace it.
pkill -f "Claude Stats.app/Contents/MacOS/Claude Stats" 2>/dev/null || true

xcodebuild \
    -project ClaudeStats.xcodeproj \
    -scheme ClaudeStats \
    -configuration Debug \
    -derivedDataPath "$DERIVED" \
    build

# Refresh Launch Services so the just-built bundle is the registered one.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP" 2>/dev/null || true

open "$APP"
echo "Launched $APP"
