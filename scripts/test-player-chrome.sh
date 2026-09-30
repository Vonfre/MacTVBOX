#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="${MACTVBOX_SDK:-$(xcrun --show-sdk-path)}"
SDK="$(cd "$SDK" && pwd -P)"
if [[ -z "${MACTVBOX_SDK:-}" && "$SDK" == *MacOSX27* && -d "${SDK%/*}/MacOSX26.5.sdk" ]]; then
    SDK="${SDK%/*}/MacOSX26.5.sdk"
fi
mkdir -p build/player-tests
swiftc -swift-version 5 -parse-as-library -sdk "$SDK" Sources/MacTVBOX/PlayerChromeController.swift scripts/testing/PlayerChromeHarness.swift -o build/player-tests/chrome-harness
build/player-tests/chrome-harness
