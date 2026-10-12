#!/bin/bash
# Signs an assembled moonleaf.app, including the nested Sparkle code.
#
# Sparkle ships ad-hoc signed, and a hardened-runtime app refuses to load a
# framework signed by someone else, so every nested binary is re-signed with our
# identity, innermost first. Run this last: any later change to the bundle
# invalidates the signature.
#
# usage: scripts/sign_app.sh [--adhoc] [--identity "<Developer ID Application: ...>"] [APP_PATH]
#   --adhoc            ad-hoc signature for local testing (no timestamp/hardened runtime)
#   --identity ID      defaults to $MP_SIGN_IDENTITY, else the first Developer ID
#                      Application identity in the keychain
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)
cd "$REPO_ROOT"

APP="build/moonleaf.app"
ADHOC=false
IDENTITY="${MP_SIGN_IDENTITY:-}"

while [ $# -gt 0 ]; do
    case "$1" in
        --adhoc) ADHOC=true; shift ;;
        --identity) IDENTITY=${2:?"--identity requires a value"}; shift 2 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *) APP=$1; shift ;;
    esac
done

if [ ! -d "$APP" ]; then
    echo "error: $APP not found; run scripts/build.sh first" >&2
    exit 1
fi

if [ "$ADHOC" = true ]; then
    IDENTITY="-"
elif [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' \
        | head -1)
    if [ -z "$IDENTITY" ]; then
        echo "error: no Developer ID Application identity found; pass --identity or --adhoc" >&2
        exit 1
    fi
fi

sign_item() {
    path=$1
    shift
    if [ ! -e "$path" ]; then
        echo "error: missing nested code: $path" >&2
        exit 1
    fi
    if [ "$IDENTITY" = "-" ]; then
        codesign --force --sign - "$@" "$path"
    else
        codesign --force --sign "$IDENTITY" --options runtime --timestamp "$@" "$path"
    fi
}

FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
VERSIONS="$FRAMEWORK/Versions/B"
if [ ! -d "$VERSIONS" ]; then
    echo "error: $APP does not embed Sparkle.framework; run scripts/build.sh first" >&2
    exit 1
fi

echo "signing with: $IDENTITY"

# Sparkle helper order and flags, per https://sparkle-project.org/documentation/sandboxing/
sign_item "$VERSIONS/XPCServices/Installer.xpc"
sign_item "$VERSIONS/XPCServices/Downloader.xpc" --preserve-metadata=entitlements
sign_item "$VERSIONS/Autoupdate"
sign_item "$VERSIONS/Updater.app"
sign_item "$FRAMEWORK"

# The bundle's helper executables (wallpaper, glasswp) live where
# codesign does not treat them as nested code, so an unsigned helper would break
# the bundle seal. The main executable is excluded: signing it while a sibling is
# still unsigned makes codesign validate the whole bundle and fail. Collect the
# list first so nothing being signed can consume the loop's stdin.
main_executable="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
helpers=()
while IFS= read -r candidate; do
    case "$(file -b "$candidate")" in
        *Mach-O*) helpers+=("$candidate") ;;
    esac
done < <(find "$APP/Contents/MacOS" "$APP/Contents/Resources" -type f -perm -u+x | sort)

for helper in "${helpers[@]}"; do
    if [ "$helper" = "$main_executable" ]; then
        continue
    fi
    sign_item "$helper" < /dev/null
done

sign_item "$APP"

codesign --verify --strict --verbose=1 "$APP"
echo "designated requirement:"
codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p'
echo "signed $APP"
