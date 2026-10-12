#!/bin/bash
# Creates the Ed25519 key pair Sparkle signs update archives with.
#
# Run once per project. The public key goes into the app's Info.plist as
# SUPublicEDKey (scripts/build.sh reads sparkle-public-key.txt); the private key
# is stored as the repository secret SPARKLE_ED_PRIVATE_KEY and never committed.
#
# Generating needs an OpenSSL with Ed25519 support: macOS's /usr/bin/openssl is
# LibreSSL and cannot do this, so a Homebrew openssl@3 is used when present.
# Release runners never generate keys - they only consume the secret.
#
# usage: scripts/generate-sparkle-keys.sh
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)
OUT_DIR="$REPO_ROOT/.sparkle"
PEM_PATH="$OUT_DIR/eddsa_private.pem"
KEY_PATH="$OUT_DIR/eddsa_priv.key"
PUB_PATH="$REPO_ROOT/sparkle-public-key.txt"

find_openssl() {
    local candidate
    for candidate in \
        /opt/homebrew/opt/openssl@3/bin/openssl \
        /opt/homebrew/bin/openssl \
        /usr/local/opt/openssl@3/bin/openssl \
        /usr/local/bin/openssl \
        openssl; do
        if command -v "$candidate" >/dev/null 2>&1 \
            && "$candidate" genpkey -algorithm ED25519 -out /dev/null 2>/dev/null; then
            command -v "$candidate"
            return 0
        fi
    done
    return 1
}

OPENSSL=$(find_openssl) || {
    echo "error: no OpenSSL with Ed25519 support found (brew install openssl@3)" >&2
    exit 1
}

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

if [ -f "$KEY_PATH" ] || [ -f "$PEM_PATH" ]; then
    echo "refusing to overwrite the existing Sparkle key in $OUT_DIR" >&2
    exit 1
fi

"$OPENSSL" genpkey -algorithm ED25519 -out "$PEM_PATH"
chmod 600 "$PEM_PATH"

python3 - "$OPENSSL" "$PEM_PATH" "$KEY_PATH" "$PUB_PATH" <<'PY'
import base64, subprocess, sys
from pathlib import Path

openssl, pem_path, key_path, pub_path = sys.argv[1], *map(Path, sys.argv[2:])
der = subprocess.check_output([openssl, "pkey", "-in", str(pem_path), "-outform", "DER"])
pub_der = subprocess.check_output([openssl, "pkey", "-in", str(pem_path), "-pubout", "-outform", "DER"])

seed_index = der.find(b"\x04\x20")
if seed_index < 0:
    raise SystemExit("Unable to locate the Ed25519 seed in the PKCS#8 key")
seed = der[seed_index + 2:seed_index + 34]
public_key = pub_der[-32:]
if len(seed) != 32 or len(public_key) != 32:
    raise SystemExit("Unexpected Ed25519 key length")

key_path.write_text(base64.b64encode(seed).decode() + "\n")
key_path.chmod(0o600)
pub_path.write_text(base64.b64encode(public_key).decode() + "\n")
PY

echo "private key: $KEY_PATH  (store as the GitHub secret SPARKLE_ED_PRIVATE_KEY)"
echo "public key:  $PUB_PATH -> $(cat "$PUB_PATH")"
