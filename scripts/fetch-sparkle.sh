#!/bin/sh
# Downloads the pinned Sparkle release and prints where its pieces live.
#
# We build with plain swiftc instead of SwiftPM/Xcode, so the framework and the
# appcast tools come from Sparkle's official .zip rather than from a package
# checkout. Everything lands under .build/sparkle-<version>/ (gitignored).
#
# The archive digest is pinned: a swapped release asset fails the build instead
# of silently shipping a foreign framework.
#
# usage: eval "$(scripts/fetch-sparkle.sh)"   # exports SPARKLE_FRAMEWORK_DIR, SPARKLE_TOOLS_DIR
set -eu

SPARKLE_VERSION=${SPARKLE_VERSION:-2.10.0}
case "$SPARKLE_VERSION" in
    2.10.0) SPARKLE_SHA256=17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959 ;;
    *) echo "error: no pinned digest for Sparkle $SPARKLE_VERSION" >&2; exit 1 ;;
esac

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CACHE_DIR="$REPO_ROOT/.build/sparkle-$SPARKLE_VERSION"
ZIP_PATH="$CACHE_DIR/Sparkle-for-Swift-Package-Manager.zip"
URL="https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-for-Swift-Package-Manager.zip"

verify_digest() {
    actual=$(shasum -a 256 "$1" | awk '{print $1}')
    if [ "$actual" != "$SPARKLE_SHA256" ]; then
        echo "error: Sparkle $SPARKLE_VERSION archive digest mismatch" >&2
        echo "  expected $SPARKLE_SHA256" >&2
        echo "  actual   $actual" >&2
        exit 1
    fi
}

if [ ! -x "$CACHE_DIR/bin/generate_appcast" ]; then
    mkdir -p "$CACHE_DIR"
    echo "downloading Sparkle $SPARKLE_VERSION" >&2
    curl -fsSL "$URL" -o "$ZIP_PATH"
    verify_digest "$ZIP_PATH"
    unzip -qo "$ZIP_PATH" -d "$CACHE_DIR"
fi

FRAMEWORK="$CACHE_DIR/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ ! -d "$FRAMEWORK" ]; then
    echo "error: Sparkle.framework not found in $CACHE_DIR" >&2
    exit 1
fi
if [ ! -x "$CACHE_DIR/bin/generate_appcast" ]; then
    echo "error: Sparkle tools not found in $CACHE_DIR/bin" >&2
    exit 1
fi

echo "SPARKLE_VERSION=$SPARKLE_VERSION"
echo "SPARKLE_FRAMEWORK_DIR=$(dirname "$FRAMEWORK")"
echo "SPARKLE_TOOLS_DIR=$CACHE_DIR/bin"
