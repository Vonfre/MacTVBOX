#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DEVELOPER="$(xcode-select -p)"
if [[ -d "$DEVELOPER/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework" || -d "$DEVELOPER/Library/Frameworks/XCTest.framework" ]]; then
    ./scripts/swift.sh test "$@"
else
    python3 scripts/testing/run-clt-tests.py "$@"
fi
