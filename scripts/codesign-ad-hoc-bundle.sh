#!/usr/bin/env bash
# Re-sign a bundle ad-hoc after post-build binary thinning.
set -euo pipefail

ROOT="${1:-}"
ENTITLEMENTS="${2:-}"
[[ -n "$ROOT" ]] || { echo "usage: $0 <app-or-directory> [entitlements.plist]" >&2; exit 2; }
[[ -e "$ROOT" ]] || { echo "error: path does not exist: $ROOT" >&2; exit 1; }

while IFS= read -r -d '' item; do
    case "$item" in
        *.o|*/CMakeFiles/*|*/CMakeCache.txt) continue ;;
    esac
    if file "$item" | grep -q 'Mach-O'; then
        codesign --force --sign - "$item"
    fi
done < <(find "$ROOT" -type d -name '*.dSYM' -prune -o -type f -print0)

while IFS= read -r bundle; do
    [[ "$bundle" == "$ROOT" ]] && continue
    codesign --force --sign - "$bundle"
done < <(
    find "$ROOT" -type d \( \
        -name '*.app' -o \
        -name '*.appex' -o \
        -name '*.bundle' -o \
        -name '*.framework' -o \
        -name '*.plugin' -o \
        -name '*.xpc' \
    \) -print | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-
)

if [[ -n "$ENTITLEMENTS" && -s "$ENTITLEMENTS" ]]; then
    codesign --force --sign - --entitlements "$ENTITLEMENTS" "$ROOT"
else
    codesign --force --sign - "$ROOT"
fi
