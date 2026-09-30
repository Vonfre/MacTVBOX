#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=2.10.0
SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
DEST="$PWD/build/sparkle-tools/$VERSION"
ARCHIVE="$DEST/Sparkle-$VERSION.tar.xz"
mkdir -p "$DEST"
if [[ ! -f "$ARCHIVE" ]]; then
    curl --fail --location --retry 3 --output "$ARCHIVE.tmp" \
        "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz"
    mv "$ARCHIVE.tmp" "$ARCHIVE"
fi
printf '%s  %s\n' "$SHA256" "$ARCHIVE" | shasum -a 256 -c - >&2
# Always extract from the checksum-verified archive instead of trusting cached tools.
tar -xf "$ARCHIVE" -C "$DEST"
printf '%s\n' "$DEST/bin"
