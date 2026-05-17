#!/usr/bin/env bash
# Run the unit-test bundle against a dedicated DerivedData path.
set -euo pipefail
cd "$(dirname "$0")/.."

bash scripts/build-ghosttykit.sh
bash scripts/build-linguist-runtime.sh
bash scripts/generate.sh

xcodebuild \
    -project ClaudeStats.xcodeproj \
    -scheme ClaudeStats \
    -configuration Debug \
    -derivedDataPath /tmp/claude-stats-build \
    -destination 'platform=macOS' \
    test
