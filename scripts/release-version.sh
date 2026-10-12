#!/bin/bash
# Derives the two version values the release pipeline stamps into the app.
#
#   CFBundleShortVersionString  human-facing version, the release tag without its
#                              leading "v" (e.g. 4.1.0.beta.1)
#   CFBundleVersion             numeric build Sparkle compares, derived from the
#                              tag so it is monotonic (beta < rc < final)
#
# Layout per version: major*1e6 + minor*1e4 + patch*1e2 + stage, where
#   11-19  beta.N   (N <= 9)
#   31-39  rc.N     (N <= 9)
#      99  final
# stage 99 keeps every prerelease below its final release, and the next patch
# starts 100 higher, so the sequence never goes backwards.
#
# usage: scripts/release-version.sh v4.1.0.beta.1      (prints KEY=VALUE lines)
set -euo pipefail

TAG=${1:-}
if [ -z "$TAG" ]; then
    echo "usage: $0 v<major>.<minor>.<patch>[.(beta|rc).<n>]" >&2
    exit 2
fi

if [[ ! "$TAG" =~ ^v([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{1,2})(\.(beta|rc)\.([0-9]))?$ ]]; then
    echo "error: '$TAG' must look like vMAJOR.MINOR.PATCH[.(beta|rc).N] with 0-99 components and a 1-9 prerelease counter" >&2
    exit 1
fi

VERSION=${TAG#v}
major=${BASH_REMATCH[1]}
minor=${BASH_REMATCH[2]}
patch=${BASH_REMATCH[3]}
stage_name=${BASH_REMATCH[5]:-}
stage_num=${BASH_REMATCH[6]:-}

stage=99
case "$stage_name" in
    beta) stage=$((10 + stage_num)) ;;
    rc) stage=$((30 + stage_num)) ;;
    '') ;;
    *) echo "error: unsupported prerelease '$stage_name'" >&2; exit 1 ;;
esac

build=$((major * 1000000 + minor * 10000 + patch * 100 + stage))

echo "SHORT_VERSION=$VERSION"
echo "BUILD_VERSION=$build"
