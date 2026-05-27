#!/usr/bin/env bash
# Remove non-runtime build artifacts from the redistributable GitTools runtime.
#
# Ruby and native gems can leave build-only artifacts next to compiled extension
# bundles. They are large, not needed at runtime, and should not be codesigned or
# shipped inside the app bundle because Sparkle binary deltas reject code-signing
# extended attributes on non-code resources.
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

removed_runtime_artifacts=0
remove_runtime_artifact() {
    local item="$1"
    [[ -e "$item" ]] || return 0
    rm -rf "$item"
    removed_runtime_artifacts=$((removed_runtime_artifacts + 1))
}

while IFS= read -r -d '' item; do
    remove_runtime_artifact "$item"
done < <(
    find "$ROOT" -depth \
        \( \
            -path '*/gems/ruby/*/cache' \
            -o -path '*/runtime/ruby/lib/ruby/gems/*/cache' \
            -o -path '*/gems/ruby/*/gems/rugged-*/vendor' \
            -o -path '*/gems/ruby/*/gems/rugged-*/ext' \
            -o -path '*/gems/ruby/*/gems/*/test' \
            -o -path '*/gems/ruby/*/gems/*/tests' \
            -o -path '*/gems/ruby/*/gems/*/spec' \
            -o -path '*/runtime/ruby/lib/ruby/gems/*/gems/*/test' \
            -o -path '*/runtime/ruby/lib/ruby/gems/*/gems/*/tests' \
            -o -path '*/runtime/ruby/lib/ruby/gems/*/gems/*/spec' \
            -o -path '*/runtime/ruby/lib/ruby/gems/*/gems/rbs-*' \
            -o -path '*/runtime/ruby/lib/ruby/gems/*/gems/typeprof-*' \
            -o -path '*/runtime/ruby/lib/ruby/gems/*/gems/debug-*' \
            -o -path '*/runtime/ruby/lib/ruby/gems/*/gems/rdoc-*' \
            -o -path '*/runtime/ruby/lib/ruby/gems/*/gems/irb-*' \
            -o -path '*/runtime/ruby/lib/ruby/gems/*/gems/test-unit-*' \
            -o -path '*/runtime/ruby/lib/ruby/gems/*/gems/minitest-*' \
            -o -path '*/runtime/ruby/lib/ruby/gems/*/gems/power_assert-*' \
            -o -path '*/runtime/ruby/lib/ruby/gems/*/specifications/rbs-*' \
            -o -path '*/runtime/ruby/lib/ruby/gems/*/specifications/typeprof-*' \
            -o -path '*/runtime/ruby/lib/ruby/gems/*/specifications/debug-*' \
            -o -path '*/runtime/ruby/lib/ruby/gems/*/specifications/rdoc-*' \
            -o -path '*/runtime/ruby/lib/ruby/gems/*/specifications/irb-*' \
            -o -path '*/runtime/ruby/lib/ruby/gems/*/specifications/test-unit-*' \
            -o -path '*/runtime/ruby/lib/ruby/gems/*/specifications/minitest-*' \
            -o -path '*/runtime/ruby/lib/ruby/gems/*/specifications/power_assert-*' \
            -o -path '*/runtime/ruby/include' \
            -o -path '*/runtime/ruby/share' \
            -o -path '*/runtime/ruby/lib/pkgconfig' \
            -o -path '*/runtime/ruby/lib/ruby/*/rdoc' \
            -o -path '*/runtime/ruby/lib/libruby-static.a' \
        \) -print0
)

if [[ "$removed_symbols" -gt 0 ]]; then
    echo "Pruned $removed_symbols debug symbol bundle(s) from GitTools runtime"
fi
if [[ "$removed_cmake_builds" -gt 0 ]]; then
    echo "Pruned $removed_cmake_builds CMake build director$( [[ "$removed_cmake_builds" -eq 1 ]] && echo "y" || echo "ies" ) from GitTools runtime"
fi
if [[ "$removed_objects" -gt 0 ]]; then
    echo "Pruned $removed_objects object file(s) from GitTools runtime"
fi
if [[ "$removed_runtime_artifacts" -gt 0 ]]; then
    echo "Pruned $removed_runtime_artifacts build-only runtime artifact(s) from GitTools runtime"
fi
