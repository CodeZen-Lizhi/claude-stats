#!/usr/bin/env bash
# Thin every Mach-O file inside an app bundle or directory to its arm64 slice.
set -euo pipefail

ROOT="${1:-}"
[[ -n "$ROOT" ]] || { echo "usage: $0 <app-or-directory>" >&2; exit 2; }
[[ -e "$ROOT" ]] || { echo "error: path does not exist: $ROOT" >&2; exit 1; }

FILE_CMD="${ARCH_THIN_FILE_CMD:-file}"
LIPO_CMD="${ARCH_THIN_LIPO_CMD:-lipo}"
thinned=0

while IFS= read -r -d '' item; do
    if ! "$FILE_CMD" "$item" | grep -q "Mach-O"; then
        continue
    fi

    archs="$("$LIPO_CMD" -archs "$item" 2>/dev/null | xargs || true)"
    if [[ "$archs" == "arm64" ]]; then
        continue
    fi
    if [[ " $archs " != *" arm64 "* ]]; then
        echo "error: cannot thin non-arm64 Mach-O file ($archs): $item" >&2
        exit 1
    fi

    mode="$(stat -f "%Lp" "$item")"
    temp="${item}.arm64-thin"
    rm -f "$temp"
    "$LIPO_CMD" -thin arm64 "$item" -output "$temp"
    chmod "$mode" "$temp"
    mv "$temp" "$item"
    thinned=$((thinned + 1))
done < <(find "$ROOT" -type d -name '*.dSYM' -prune -o -type f -print0)

echo "Thinned $thinned Mach-O file(s) to arm64 under $ROOT"
