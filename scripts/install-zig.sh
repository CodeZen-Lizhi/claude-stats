#!/usr/bin/env bash
# Install the Zig toolchain required by Ghostty into a repo-local .tools folder.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${ZIG_VERSION:-0.15.2}"
TOOLS_DIR="$PWD/.tools"
INSTALL_DIR="$TOOLS_DIR/zig-$VERSION"
ZIG_BIN="$INSTALL_DIR/zig"

if [[ -x "$ZIG_BIN" ]]; then
    echo "==> Zig $VERSION already installed at $ZIG_BIN"
    "$ZIG_BIN" version
    exit 0
fi

case "$(uname -m)" in
    arm64) ZIG_ARCH="aarch64" ;;
    x86_64)
        echo "error: Claude Stats now supports Apple Silicon Macs only; install Zig on an arm64 Mac." >&2
        exit 1
        ;;
    *)
        echo "error: unsupported macOS architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

ARCHIVE="zig-$ZIG_ARCH-macos-$VERSION.tar.xz"
URL="https://ziglang.org/download/$VERSION/$ARCHIVE"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zig-install.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "==> Downloading Zig $VERSION for $ZIG_ARCH-macos"
mkdir -p "$TOOLS_DIR"
curl --fail --location --retry 3 --output "$TMP_DIR/$ARCHIVE" "$URL"

echo "==> Installing Zig to $INSTALL_DIR"
rm -rf "$INSTALL_DIR"
tar -xJf "$TMP_DIR/$ARCHIVE" -C "$TMP_DIR"
mv "$TMP_DIR/zig-$ZIG_ARCH-macos-$VERSION" "$INSTALL_DIR"

"$ZIG_BIN" version
