#!/bin/bash
# Generates the in-repo Homebrew cask for a published release.
#
# The cask is generated, not hand-maintained: the version and sha256 come from
# the release job. It is kept in-tree so a tap can adopt it later without
# rewriting it; nothing publishes to a tap today.
#
# usage: scripts/generate-cask.sh --version 4.1.0.beta.1 --sha256 <hex> [--tag v4.1.0.beta.1]
#                                 [--output Casks/moonleaf.rb]
set -euo pipefail

VERSION=
SHA256=
TAG=
OUTPUT=Casks/moonleaf.rb
REPO=shiquda/moonleaf

while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION=${2:?"--version requires a value"}; shift 2 ;;
        --sha256) SHA256=${2:?"--sha256 requires a value"}; shift 2 ;;
        --tag) TAG=${2:?"--tag requires a value"}; shift 2 ;;
        --output) OUTPUT=${2:?"--output requires a value"}; shift 2 ;;
        --repo) REPO=${2:?"--repo requires a value"}; shift 2 ;;
        -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

[ -n "$VERSION" ] || { echo "error: --version is required" >&2; exit 2; }
[ -n "$SHA256" ] || { echo "error: --sha256 is required" >&2; exit 2; }
case "$SHA256" in
    *[!0-9a-f]*|'') echo "error: --sha256 must be a lowercase hex digest" >&2; exit 1 ;;
esac
if [ ${#SHA256} -ne 64 ]; then
    echo "error: --sha256 must be 64 hex characters" >&2
    exit 1
fi
[ -n "$TAG" ] || TAG="v$VERSION"

mkdir -p "$(dirname "$OUTPUT")"
cat > "$OUTPUT" << EOF
cask "moonleaf" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$REPO/releases/download/v#{version}/moonleaf.dmg"
  name "moonleaf"
  desc "Wallpaper engine with shuffling, per-desktop wallpapers and a wallpaper browser"
  homepage "https://shiquda.github.io/moonleaf"

  livecheck do
    url "https://github.com/$REPO/releases/latest/download/latest"
    regex(/^v?(\d+(?:\.\d+)*(?:\.beta\.\d+)?)$/i)
  end

  auto_updates true
  depends_on macos: :monterey

  app "moonleaf.app"

  zap trash: [
    "~/.config/moonleaf",
    "~/.local/share/macpaper",
    "~/Library/LaunchAgents/com.naomisphere.macpaper.app.plist",
  ]
end
EOF

echo "wrote $OUTPUT (version $VERSION)"
