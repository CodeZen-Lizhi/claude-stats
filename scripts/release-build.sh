#!/usr/bin/env bash
# Build a Release Claude Stats.app and package it for distribution into ./dist/.
#
# Two modes, selected automatically by whether SIGN_IDENTITY is set:
#
#   • Signed mode (SIGN_IDENTITY set): codesign with a Developer ID Application
#     identity + hardened runtime, package a DMG, notarize it with notarytool,
#     and staple the ticket.  Output: dist/ClaudeStats-<version>.dmg
#
#   • Unsigned mode (SIGN_IDENTITY unset): ad-hoc sign, package both a DMG and a
#     .zip.  Gatekeeper will warn on first launch (right-click ▸ Open).
#     Output: dist/ClaudeStats-<version>.dmg and dist/ClaudeStats-<version>.zip
#
# Usage: bash scripts/release-build.sh [version]
#   [version]  version label for the artifact file names; defaults to the
#              MARKETING_VERSION currently in project.yml.
#
# Environment (signed mode):
#   SIGN_IDENTITY              codesign identity, e.g. "Developer ID Application: Foo (TEAMID)"
#   APPLE_TEAM_ID              10-char Apple Developer Team ID
#   APPLE_ID + APP_PASSWORD    Apple ID + app-specific password for notarytool
#   NOTARY_KEYCHAIN_PROFILE    (alternative to APPLE_ID/APP_PASSWORD) a stored notarytool profile
#
# The finished artifacts are written to ./dist/.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED=/tmp/claude-stats-release
PRODUCTS="$DERIVED/Build/Products/Release"
APP="$PRODUCTS/Claude Stats.app"
DIST="$PWD/dist"

VERSION="${1:-$(grep -E '^[[:space:]]*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')}"
[[ -n "$VERSION" ]] || { echo "error: could not determine version" >&2; exit 1; }
DMG="$DIST/ClaudeStats-$VERSION.dmg"
ZIP="$DIST/ClaudeStats-$VERSION.zip"

SIGNED=0
[[ -n "${SIGN_IDENTITY:-}" ]] && SIGNED=1

echo "==> Building Claude Stats $VERSION (Release, $([[ $SIGNED -eq 1 ]] && echo "signed + notarized" || echo "unsigned"))"
bash scripts/generate.sh

rm -rf "$DERIVED" "$DIST"
mkdir -p "$DIST"

XCODE_SIGN_ARGS=()
if [[ $SIGNED -eq 1 ]]; then
    echo "==> Signing with: $SIGN_IDENTITY (hardened runtime)"
    XCODE_SIGN_ARGS=(
        CODE_SIGN_STYLE=Manual
        CODE_SIGN_IDENTITY="$SIGN_IDENTITY"
        ENABLE_HARDENED_RUNTIME=YES
        OTHER_CODE_SIGN_FLAGS="--timestamp"
    )
    [[ -n "${APPLE_TEAM_ID:-}" ]] && XCODE_SIGN_ARGS+=(DEVELOPMENT_TEAM="$APPLE_TEAM_ID")
else
    XCODE_SIGN_ARGS=(CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Automatic ENABLE_HARDENED_RUNTIME=NO)
fi

xcodebuild \
    -project ClaudeStats.xcodeproj \
    -scheme ClaudeStats \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    "${XCODE_SIGN_ARGS[@]}" \
    build

[[ -d "$APP" ]] || { echo "error: build did not produce $APP" >&2; exit 1; }

make_dmg() {
    local stage; stage="$(mktemp -d)"
    cp -R "$APP" "$stage/"
    ln -s /Applications "$stage/Applications"
    hdiutil create -volname "Claude Stats" -srcfolder "$stage" -ov -format UDZO "$DMG"
    rm -rf "$stage"
}

if [[ $SIGNED -eq 0 ]]; then
    echo "==> Packaging DMG + zip (unsigned)"
    make_dmg
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "==> Done (unsigned): $DMG, $ZIP"
    ls -la "$DIST"
    exit 0
fi

echo "==> Verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Packaging DMG"
make_dmg

echo "==> Signing DMG"
codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"

echo "==> Submitting to Apple notary service (this can take a few minutes)"
NOTARY_ARGS=()
if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    NOTARY_ARGS=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
elif [[ -n "${APPLE_ID:-}" && -n "${APP_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
    NOTARY_ARGS=(--apple-id "$APPLE_ID" --password "$APP_PASSWORD" --team-id "$APPLE_TEAM_ID")
else
    echo "error: notarization needs NOTARY_KEYCHAIN_PROFILE or APPLE_ID + APP_PASSWORD + APPLE_TEAM_ID" >&2
    exit 1
fi
xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG" || true

echo "==> Done (signed + notarized): $DMG"
ls -la "$DIST"
