#!/bin/bash
set -euo pipefail
# A newer CLT can select the macOS 27 SDK without the matching SwiftUI macro
# plugin. Prefer the installed macOS 26.5 SDK in that specific environment.
# Users can always override via MACTVBOX_SDK.
SDK="${MACTVBOX_SDK:-$(xcrun --show-sdk-path)}"
SDK="$(cd "$SDK" && pwd -P)"
if [[ -z "${MACTVBOX_SDK:-}" && "$SDK" == *MacOSX27* && -d "${SDK%/*}/MacOSX26.5.sdk" ]]; then
    SDK="${SDK%/*}/MacOSX26.5.sdk"
fi
exec swift "$@" --sdk "$SDK"
