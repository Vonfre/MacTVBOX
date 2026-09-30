#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
TAG="${1:-v$VERSION}"
[[ "$TAG" == "v$VERSION" ]] || { echo "Tag and Info.plist version disagree" >&2; exit 1; }
OUT="$PWD/build/release"
APP="$OUT/MacTVBOX.app"
ZIP="$OUT/MacTVBOX-$VERSION-universal.zip"
TOOLS="$(./scripts/fetch-sparkle-tools.sh)"
SIGN_ARGS=(--account app.mactvbox.desktop)
if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
    SIGN_ARGS=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
fi
APP_PATH="$APP" ARCHS='arm64 x86_64' ./scripts/build-app.sh
[[ "$(lipo -archs "$APP/Contents/MacOS/MacTVBOX")" == *arm64* ]]
[[ "$(lipo -archs "$APP/Contents/MacOS/MacTVBOX")" == *x86_64* ]]
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
SIGNATURE="$("$TOOLS/sign_update" "${SIGN_ARGS[@]}" -p "$ZIP")"
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$APP/Contents/Info.plist")"
xcrun swift -sdk "$(xcrun --show-sdk-path)" scripts/verify-update.swift "$ZIP" "$SIGNATURE" "$PUBLIC_KEY"
python3 scripts/make-appcast.py --plist "$APP/Contents/Info.plist" --archive "$ZIP" \
    --signature "$SIGNATURE" --tag "$TAG" --output "$OUT/appcast.xml"
"$TOOLS/sign_update" "${SIGN_ARGS[@]}" "$OUT/appcast.xml"
"$TOOLS/sign_update" "${SIGN_ARGS[@]}" --verify "$OUT/appcast.xml"
(cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" appcast.xml > SHA256SUMS)
echo "Release assets: $ZIP, $OUT/appcast.xml, $OUT/SHA256SUMS"
