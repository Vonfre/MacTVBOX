#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "${MACTVBOX_LIVE_NATIVE:-}" == 1 && $# -ge 1 ]] || { echo 'MACTVBOX_LIVE_NATIVE=1 scripts/test-native-playback.sh <jianpian|guazi|jpys> [query]' >&2; exit 2; }
SDK="${MACTVBOX_SDK:-$(xcrun --show-sdk-path)}"
SDK="$(cd "$SDK" && pwd -P)"
if [[ -z "${MACTVBOX_SDK:-}" && "$SDK" == *MacOSX27* && -d "${SDK%/*}/MacOSX26.5.sdk" ]]; then SDK="${SDK%/*}/MacOSX26.5.sdk"; fi
OUT="$PWD/build/native-playback-tests"
mkdir -p "$OUT"
sed '/^import MacTVBOXCore$/d' Sources/MacTVBOX/PlayerController.swift > "$OUT/PlayerController.swift"
swiftc -swift-version 5 -parse-as-library -sdk "$SDK" Sources/MacTVBOXCore/*.swift "$OUT/PlayerController.swift" scripts/testing/NativePlaybackProbe.swift -o "$OUT/probe"
"$OUT/probe" "$@"
