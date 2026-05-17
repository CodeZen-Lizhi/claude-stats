#!/usr/bin/env bash
# Build Ghostty's embeddable macOS library and resources for Claude Stats.
set -euo pipefail
cd "$(dirname "$0")/.."

GHOSTTY_DIR="$PWD/ThirdParty/ghostty"
XCFW="$GHOSTTY_DIR/macos/GhosttyKit.xcframework"
EMBED_RESOURCES="$PWD/GhosttyEmbed/Resources"
XCFRAMEWORK_TARGET="${GHOSTTY_XCFRAMEWORK_TARGET:-native}"
OPTIMIZE="${GHOSTTY_OPTIMIZE:-Debug}"

case "$OPTIMIZE" in
    Debug|ReleaseSafe|ReleaseFast|ReleaseSmall) ;;
    *)
        echo "error: invalid GHOSTTY_OPTIMIZE '$OPTIMIZE'" >&2
        echo "hint: use one of Debug, ReleaseSafe, ReleaseFast, ReleaseSmall" >&2
        exit 1
        ;;
esac

if [[ ! -d "$GHOSTTY_DIR" ]]; then
    echo "error: Ghostty submodule is missing at $GHOSTTY_DIR" >&2
    echo "hint: git submodule update --init --recursive" >&2
    exit 1
fi

ZIG_BIN="${ZIG_BIN:-}"
if [[ -z "$ZIG_BIN" ]]; then
    HOMEBREW_ZIG_PREFIX="$(brew --prefix zig@0.15 2>/dev/null || true)"
    for candidate in \
        "$HOMEBREW_ZIG_PREFIX/bin/zig" \
        "$PWD/.tools/zig-0.15.2/zig" \
        "/opt/homebrew/opt/zig@0.15/bin/zig" \
        "/usr/local/opt/zig@0.15/bin/zig" \
        "$(command -v zig || true)"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            ZIG_BIN="$candidate"
            break
        fi
    done
fi

if [[ -z "$ZIG_BIN" ]]; then
    echo "error: zig is required to build GhosttyKit.xcframework" >&2
    echo "hint: run scripts/install-zig.sh to install Zig 0.15.2 locally, then rerun this script" >&2
    exit 1
fi

ZIG_VERSION="$("$ZIG_BIN" version)"
if [[ "$ZIG_VERSION" != "0.15.2" ]]; then
    echo "error: Zig 0.15.2 is required to build GhosttyKit.xcframework (found $ZIG_VERSION at $ZIG_BIN)" >&2
    echo "hint: run scripts/install-zig.sh or set ZIG_BIN to a Zig 0.15.2 executable" >&2
    exit 1
fi

echo "==> Building GhosttyKit.xcframework (optimize=$OPTIMIZE, target=$XCFRAMEWORK_TARGET)"
(
    cd "$GHOSTTY_DIR"
    "$ZIG_BIN" build \
        -Demit-xcframework=true \
        -Demit-macos-app=false \
        -Doptimize="$OPTIMIZE" \
        -Dxcframework-target="$XCFRAMEWORK_TARGET"
)

[[ -d "$XCFW" ]] || {
    echo "error: expected $XCFW to be generated" >&2
    exit 1
}

echo "==> Syncing Ghostty resources"
mkdir -p "$EMBED_RESOURCES"
rm -rf "$EMBED_RESOURCES"/*
if [[ -d "$GHOSTTY_DIR/zig-out/share/ghostty" ]]; then
    ditto "$GHOSTTY_DIR/zig-out/share/ghostty" "$EMBED_RESOURCES"
fi
for name in terminfo zsh fish bash-completion; do
    if [[ -d "$GHOSTTY_DIR/zig-out/share/$name" ]]; then
        ditto "$GHOSTTY_DIR/zig-out/share/$name" "$EMBED_RESOURCES/$name"
    fi
done

echo "==> Ready: $XCFW"
