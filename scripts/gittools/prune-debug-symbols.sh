#!/usr/bin/env bash
# Remove non-runtime build artifacts from the redistributable GitTools runtime.
#
# Ruby and native gems can leave *.dSYM directories next to compiled extension
# bundles, plus object files and CMake build directories. They are large, not
# needed at runtime, and should not be codesigned or shipped inside the app
# bundle because Sparkle binary deltas reject code-signing extended attributes on
# non-code resources.
set -euo pipefail

ROOT="${1:-}"
[[ -n "$ROOT" ]] || { echo "usage: $0 <gittools-runtime-dir>" >&2; exit 2; }
[[ -d "$ROOT" ]] || { echo "error: runtime dir not found: $ROOT" >&2; exit 1; }

removed_symbols=0
while IFS= read -r -d '' item; do
    rm -rf "$item"
    removed_symbols=$((removed_symbols + 1))
done < <(find "$ROOT" -type d -name '*.dSYM' -prune -print0)

removed_cmake_builds=0
while IFS= read -r -d '' item; do
    build_dir="$(dirname "$item")"
    rm -rf "$build_dir"
    removed_cmake_builds=$((removed_cmake_builds + 1))
done < <(find "$ROOT" -type f -name 'CMakeCache.txt' -print0)

removed_objects=0
while IFS= read -r -d '' item; do
    rm -f "$item"
    removed_objects=$((removed_objects + 1))
done < <(find "$ROOT" -type f -name '*.o' -print0)

if [[ "$removed_symbols" -gt 0 ]]; then
    echo "Pruned $removed_symbols debug symbol bundle(s) from GitTools runtime"
fi
if [[ "$removed_cmake_builds" -gt 0 ]]; then
    echo "Pruned $removed_cmake_builds CMake build director$( [[ "$removed_cmake_builds" -eq 1 ]] && echo "y" || echo "ies" ) from GitTools runtime"
fi
if [[ "$removed_objects" -gt 0 ]]; then
    echo "Pruned $removed_objects object file(s) from GitTools runtime"
fi
