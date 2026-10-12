#!/bin/bash
# Packages a built moonleaf.app into the release disk image.
#
# The layout is part of the update contract: the volume is named "moonleaf",
# moonleaf.app sits at its root, and the asset is published as moonleaf.dmg, so
# the in-app updater (Updater.swift) and moonleaf/updater.sh can mount it and
# copy /Volumes/moonleaf/moonleaf.app into /Applications.
#
# usage: scripts/package_dmg.sh [app-bundle] [output-dmg]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"
APP="${1:-$REPO_ROOT/build/moonleaf.app}"
OUT="${2:-$REPO_ROOT/build/moonleaf.dmg}"
VOLNAME="moonleaf"
ICON="$REPO_ROOT/artwork/icns/moonleaf/moonleaf.icns"

if [[ ! -d "$APP" ]]; then
    echo "error: app bundle not found: $APP" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
STAGING="$(mktemp -d)/dmg"
RW_DMG="$(mktemp -u).dmg"
MOUNTPOINT="$(mktemp -d)"

cleanup() {
    hdiutil detach "$MOUNTPOINT" >/dev/null 2>&1 || true
    rm -rf "$STAGING" "$MOUNTPOINT" "$RW_DMG"
}
trap cleanup EXIT

echo "packaging moonleaf $VERSION -> $OUT"

mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/moonleaf.app"
ln -s /Applications "$STAGING/Applications"
if [[ -f "$ICON" ]]; then
    cp "$ICON" "$STAGING/.VolumeIcon.icns"
fi

# Build writable, stamp the volume's custom-icon bit, then compress: the bit
# only sticks on a mounted volume, so a single-step create would drop the icon.
hdiutil create \
    -volname "$VOLNAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    "$RW_DMG" >/dev/null

hdiutil attach "$RW_DMG" -mountpoint "$MOUNTPOINT" -nobrowse -readwrite -noautoopen >/dev/null
if command -v SetFile >/dev/null 2>&1 && [[ -f "$MOUNTPOINT/.VolumeIcon.icns" ]]; then
    SetFile -a C "$MOUNTPOINT"
fi
hdiutil detach "$MOUNTPOINT" >/dev/null

rm -f "$OUT"
hdiutil convert "$RW_DMG" -format UDZO -o "$OUT" >/dev/null

OUT_DIR="$(dirname "$OUT")"
# Signing the image, notarizing it, and stapling the ticket all rewrite the file,
# so this digest only describes the freshly packaged image. The release workflow
# recomputes it once those steps are done.
( cd "$OUT_DIR" && shasum -a 256 "$(basename "$OUT")" > "$(basename "$OUT").sha256" )

echo "created $OUT ($(du -h "$OUT" | cut -f1))"
cat "$OUT.sha256"
