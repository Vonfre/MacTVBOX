#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${MACTVBOX_LIVE_SPIDER:-}" != "1" ]]; then
    echo "Opt in with MACTVBOX_LIVE_SPIDER=1 (short, muted live media decoding; no files saved)." >&2
    exit 2
fi
SDK="${MACTVBOX_SDK:-$(xcrun --show-sdk-path)}"
SDK="$(cd "$SDK" && pwd -P)"
if [[ -z "${MACTVBOX_SDK:-}" && "$SDK" == *MacOSX27* && -d "${SDK%/*}/MacOSX26.5.sdk" ]]; then SDK="${SDK%/*}/MacOSX26.5.sdk"; fi
mkdir -p build/native-spider-tests
swiftc -swift-version 5 -parse-as-library -sdk "$SDK" Sources/MacTVBOXCore/*.swift \
    scripts/testing/NativeSpiderPlaybackProbe.swift -o build/native-spider-tests/playback-probe
build/native-spider-tests/playback-probe
