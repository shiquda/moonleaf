#!/bin/bash
# Generates the Sparkle appcast for a release disk image.
#
# The appcast is what installed copies poll (SUFeedURL ->
# releases/latest/download/appcast.xml), so the enclosure must point at the
# published asset and carry an EdDSA signature made with the private key whose
# public half is compiled into the app as SUPublicEDKey.
#
# usage: scripts/generate-appcast.sh --tag v4.1.0.beta.1 --dmg dist/moonleaf.dmg
#                                    [--notes FILE] [--output dist/appcast.xml]
#                                    [--repo shiquda/moonleaf]
#
# The private key comes from $SPARKLE_ED_PRIVATE_KEY (CI secret, base64 seed) or
# from .sparkle/eddsa_priv.key (scripts/generate-sparkle-keys.sh).
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

TAG=
DMG=
NOTES=
OUTPUT=
REPO=shiquda/moonleaf

while [ $# -gt 0 ]; do
    case "$1" in
        --tag) TAG=${2:?"--tag requires a value"}; shift 2 ;;
        --dmg) DMG=${2:?"--dmg requires a value"}; shift 2 ;;
        --notes) NOTES=${2:?"--notes requires a value"}; shift 2 ;;
        --output) OUTPUT=${2:?"--output requires a value"}; shift 2 ;;
        --repo) REPO=${2:?"--repo requires a value"}; shift 2 ;;
        -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$TAG" ] || [ -z "$DMG" ]; then
    echo "error: --tag and --dmg are required" >&2
    exit 2
fi
if [ ! -f "$DMG" ]; then
    echo "error: $DMG not found" >&2
    exit 1
fi

eval "$("$SCRIPT_DIR/fetch-sparkle.sh")"

KEY_FILE=$(mktemp)
STAGING=$(mktemp -d)
trap 'rm -f "$KEY_FILE"; rm -rf "$STAGING"' EXIT

if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
    printf '%s\n' "$SPARKLE_ED_PRIVATE_KEY" > "$KEY_FILE"
elif [ -f "$REPO_ROOT/.sparkle/eddsa_priv.key" ]; then
    cp "$REPO_ROOT/.sparkle/eddsa_priv.key" "$KEY_FILE"
else
    echo "error: no signing key: set SPARKLE_ED_PRIVATE_KEY or run scripts/generate-sparkle-keys.sh" >&2
    exit 1
fi

# generate_appcast derives each item from an archive in the source directory and
# picks up release notes from a file named after the archive (moonleaf.md).
cp "$DMG" "$STAGING/$(basename "$DMG")"
if [ -n "$NOTES" ]; then
    if [ ! -f "$NOTES" ]; then
        echo "error: notes file $NOTES not found" >&2
        exit 1
    fi
    cp "$NOTES" "$STAGING/$(basename "${DMG%.*}").md"
fi

if [ -z "$OUTPUT" ]; then
    OUTPUT="$(dirname "$DMG")/appcast.xml"
fi
mkdir -p "$(dirname "$OUTPUT")"

echo "generating appcast $OUTPUT for $TAG"
"$SPARKLE_TOOLS_DIR/generate_appcast" \
    --ed-key-file "$KEY_FILE" \
    --embed-release-notes \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    --link "https://github.com/$REPO/releases/tag/$TAG" \
    --maximum-deltas 0 \
    -o "$OUTPUT" \
    "$STAGING"

if [ ! -s "$OUTPUT" ]; then
    echo "error: appcast was not generated" >&2
    exit 1
fi

# Fail closed if the item Sparkle will install is unsigned. Each release
# publishes a single disk image, so the feed carries one item.
signature=$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$OUTPUT" | head -1)
if [ -z "$signature" ]; then
    echo "error: $OUTPUT has no sparkle:edSignature (does the app declare SUPublicEDKey?)" >&2
    exit 1
fi
"$SPARKLE_TOOLS_DIR/sign_update" --verify --ed-key-file "$KEY_FILE" "$DMG" "$signature" \
    || { echo "error: the appcast signature does not verify against $DMG" >&2; exit 1; }

echo "created $OUTPUT"
