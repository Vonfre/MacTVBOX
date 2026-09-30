#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="${MACTVBOX_SDK:-$(xcrun --show-sdk-path)}"
SDK="$(cd "$SDK" && pwd -P)"
if [[ -z "${MACTVBOX_SDK:-}" && "$SDK" == *MacOSX27* && -d "${SDK%/*}/MacOSX26.5.sdk" ]]; then
    SDK="${SDK%/*}/MacOSX26.5.sdk"
fi
OUT="$PWD/build/player-tests"
mkdir -p "$OUT"
if [[ ! -f build/fixtures/media.mp4 ]]; then
    swift -sdk "$SDK" scripts/create-test-media.swift build/fixtures/media.mp4
fi
# Compile the actual controller with an isolated in-memory AppStore. Core sources
# are in the same module, so remove only the module import from the copied file.
sed '/^import MacTVBOXCore$/d' Sources/MacTVBOX/PlayerController.swift > "$OUT/PlayerController.swift"
swiftc -swift-version 5 -parse-as-library -sdk "$SDK" Sources/MacTVBOXCore/*.swift \
    "$OUT/PlayerController.swift" scripts/testing/PlayerHarness.swift -o "$OUT/player-harness"
"$OUT/player-harness" "$PWD/build/fixtures/media.mp4"
