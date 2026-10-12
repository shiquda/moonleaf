#!/bin/bash
# Fail-closed checks on a staged release: hashes, appcast metadata, signature,
# and the version actually stamped inside the disk image.
#
# usage: scripts/verify-release.sh --appcast dist/appcast.xml --dmg dist/moonleaf.dmg
#                                  [--short 4.1.0.beta.1] [--build 4010011]
#                                  [--tag v4.1.0.beta.1] [--repo shiquda/moonleaf]
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

APPCAST=
DMG=
SHORT=
BUILD=
TAG=
REPO=shiquda/moonleaf

while [ $# -gt 0 ]; do
    case "$1" in
        --appcast) APPCAST=${2:?"--appcast requires a value"}; shift 2 ;;
        --dmg) DMG=${2:?"--dmg requires a value"}; shift 2 ;;
        --short) SHORT=${2:?"--short requires a value"}; shift 2 ;;
        --build) BUILD=${2:?"--build requires a value"}; shift 2 ;;
        --tag) TAG=${2:?"--tag requires a value"}; shift 2 ;;
        --repo) REPO=${2:?"--repo requires a value"}; shift 2 ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$APPCAST" ] || [ -z "$DMG" ]; then
    echo "error: --appcast and --dmg are required" >&2
    exit 2
fi
[ -f "$APPCAST" ] || { echo "error: $APPCAST not found" >&2; exit 1; }
[ -f "$DMG" ] || { echo "error: $DMG not found" >&2; exit 1; }

eval "$("$SCRIPT_DIR/fetch-sparkle.sh")"

fail() { echo "FAIL: $1" >&2; exit 1; }
attr() { sed -n "s/.* $1=\"\([^\"]*\)\".*/\1/p" "$APPCAST" | head -1; }
elem() { sed -n "s/.*<$1>\([^<]*\)<\/$1>.*/\1/p" "$APPCAST" | head -1; }

# 1. The published checksum must describe the disk image we are about to ship.
SHA_FILE="$DMG.sha256"
[ -f "$SHA_FILE" ] || fail "missing $SHA_FILE"
( cd "$(dirname "$DMG")" && shasum -a 256 -c "$(basename "$SHA_FILE")" >/dev/null ) \
    || fail "sha256 mismatch for $DMG"
echo "ok: sha256 matches $(basename "$SHA_FILE")"

# 2. Appcast metadata and signature.
URL=$(attr url)
VERSION=$(elem "sparkle:version")
SHORT_VERSION=$(elem "sparkle:shortVersionString")
SIGNATURE=$(attr "sparkle:edSignature")
[ -n "$URL" ] || fail "appcast has no enclosure url"
[ -n "$VERSION" ] || fail "appcast has no sparkle:version"
[ -n "$SHORT_VERSION" ] || fail "appcast has no sparkle:shortVersionString"
[ -n "$SIGNATURE" ] || fail "appcast has no sparkle:edSignature"

[ "$(basename "$URL")" = "$(basename "$DMG")" ] \
    || fail "appcast url $URL does not point at $(basename "$DMG")"
if [ -n "$TAG" ]; then
    [ "$URL" = "https://github.com/$REPO/releases/download/$TAG/$(basename "$DMG")" ] \
        || fail "appcast url $URL is not the $TAG asset URL"
fi
echo "ok: appcast enclosure $URL"

# 3. Enclosure signature must verify against our own key.
KEY_FILE=$(mktemp)
trap 'rm -f "$KEY_FILE"' EXIT
if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
    printf '%s\n' "$SPARKLE_ED_PRIVATE_KEY" > "$KEY_FILE"
elif [ -f "$REPO_ROOT/.sparkle/eddsa_priv.key" ]; then
    cp "$REPO_ROOT/.sparkle/eddsa_priv.key" "$KEY_FILE"
else
    echo "error: no signing key: set SPARKLE_ED_PRIVATE_KEY or run scripts/generate-sparkle-keys.sh" >&2
    exit 1
fi
"$SPARKLE_TOOLS_DIR/sign_update" --verify --ed-key-file "$KEY_FILE" "$DMG" "$SIGNATURE" \
    || fail "the appcast signature does not match $DMG"
echo "ok: appcast signature verifies"

# 4. The version inside the disk image is the one the appcast advertises.
MOUNTPOINT=$(mktemp -d)
cleanup_mount() { hdiutil detach "$MOUNTPOINT" >/dev/null 2>&1 || true; rmdir "$MOUNTPOINT" 2>/dev/null || true; }
trap 'cleanup_mount; rm -f "$KEY_FILE"' EXIT
hdiutil attach "$DMG" -mountpoint "$MOUNTPOINT" -nobrowse -readonly -noautoopen >/dev/null
PLIST="$MOUNTPOINT/moonleaf.app/Contents/Info.plist"
[ -f "$PLIST" ] || { cleanup_mount; fail "the disk image has no moonleaf.app/Contents/Info.plist"; }
DMG_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")
DMG_SHORT=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
codesign --verify --strict --verbose=1 "$MOUNTPOINT/moonleaf.app" \
    || { cleanup_mount; fail "the app inside the image has an invalid signature"; }
cleanup_mount

[ "$DMG_BUILD" = "$VERSION" ] \
    || fail "bundle CFBundleVersion $DMG_BUILD does not match appcast sparkle:version $VERSION"
[ "$DMG_SHORT" = "$SHORT_VERSION" ] \
    || fail "bundle CFBundleShortVersionString $DMG_SHORT does not match appcast $SHORT_VERSION"
if [ -n "$BUILD" ] && [ "$DMG_BUILD" != "$BUILD" ]; then
    fail "bundle CFBundleVersion $DMG_BUILD is not the expected build $BUILD"
fi
if [ -n "$SHORT" ] && [ "$DMG_SHORT" != "$SHORT" ]; then
    fail "bundle CFBundleShortVersionString $DMG_SHORT is not the expected version $SHORT"
fi
echo "ok: bundle version $DMG_SHORT (build $DMG_BUILD) matches the appcast"
echo "verified $DMG"
