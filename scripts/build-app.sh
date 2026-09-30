#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIGURATION="${CONFIGURATION:-release}"
ARCHS="${ARCHS:-$(uname -m)}"
APP="${APP_PATH:-$PWD/build/MacTVBOX.app}"
if pgrep -fx "$APP/Contents/MacOS/MacTVBOX" >/dev/null; then
    echo "请先退出正在运行的 MacTVBOX，再重新打包（避免覆盖运行中的二进制文件）。" >&2
    exit 1
fi
# SwiftPM's multi-arch build also packages Sparkle's universal binary artifact.
ARGS=()
for ARCH in $ARCHS; do
    case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1;; esac
    ARGS+=(--arch "$ARCH")
done
./scripts/swift.sh build -c "$CONFIGURATION" "${ARGS[@]}"
BIN_DIR="$(./scripts/swift.sh build -c "$CONFIGURATION" "${ARGS[@]}" --show-bin-path)"
FRAMEWORK="$(find .build/artifacts -type d -path '*/macos-*/Sparkle.framework' -print -quit)"
if [[ -z "$FRAMEWORK" ]]; then
    echo "Sparkle.framework missing from resolved SwiftPM artifacts" >&2
    exit 1
fi
# Recreate the bundle so old executable / framework resources cannot leak into a release.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/MacTVBOX" "$APP/Contents/MacOS/MacTVBOX"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Sparkle-LICENSE.txt "$APP/Contents/Resources/Sparkle-LICENSE.txt"
ditto "$FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
# Preserve Sparkle's upstream signatures on nested XPC / installer components.
# This default is ad-hoc; Developer ID notarization requires an Apple certificate.
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP ($(lipo -archs "$APP/Contents/MacOS/MacTVBOX"))"
