#!/usr/bin/env bash
# Verify every Mach-O file inside an app bundle or directory is arm64-only.
set -euo pipefail

ROOT="${1:-}"
[[ -n "$ROOT" ]] || { echo "usage: $0 <app-or-directory>" >&2; exit 2; }
[[ -e "$ROOT" ]] || { echo "error: path does not exist: $ROOT" >&2; exit 1; }

FILE_CMD="${ARCH_VERIFY_FILE_CMD:-file}"
LIPO_CMD="${ARCH_VERIFY_LIPO_CMD:-lipo}"
EXPECTED_ARCHS="arm64"
failures=0

while IFS= read -r -d '' item; do
    if ! "$FILE_CMD" "$item" | grep -q "Mach-O"; then
        continue
    fi

    archs="$("$LIPO_CMD" -archs "$item" 2>/dev/null | xargs || true)"
    if [[ "$archs" != "$EXPECTED_ARCHS" ]]; then
        echo "error: expected $EXPECTED_ARCHS, found '${archs:-unknown}' in $item" >&2
        failures=$((failures + 1))
    fi
done < <(find "$ROOT" -type d -name '*.dSYM' -prune -o -type f -print0)

if [[ $failures -ne 0 ]]; then
    echo "error: found $failures non-arm64 Mach-O file(s) under $ROOT" >&2
    exit 1
fi

echo "All Mach-O files are arm64-only: $ROOT"
