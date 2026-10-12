# Development

## Building

- `scripts/build.sh` — build for the host architecture (`arm64` or `x86_64`).
- `scripts/build.sh --all --yes` — build a universal binary without the interactive confirmation.

Sparkle is fetched from its official release archive (digest-pinned in `fetch-sparkle.sh`) into `.build/` on the first build, so building needs network access.

## Releases

A release is published by [`.github/workflows/release.yml`](./.github/workflows/release.yml), either from a pushed `v*` tag or by dispatching the workflow with a tag name (if the tag does not exist yet it is created at the tip of `main`). The tag must look like `v4.1.0` or `v4.1.0.beta.1`; `release-version.sh` turns it into the user-facing version plus the monotonic numeric `CFBundleVersion` that Sparkle compares.

| Script | Purpose |
| --- | --- |
| `release-version.sh <tag>` | Prints the user-facing version and the numeric build version for a tag. |
| `fetch-sparkle.sh` | Downloads the pinned Sparkle release into `.build/` and exports its framework and tool paths. |
| `sign_app.sh` | Re-signs Sparkle's nested code and every helper binary, then the app (Developer ID + hardened runtime; `--adhoc` for local builds). |
| `package_dmg.sh` | Builds `moonleaf.dmg` (volume `moonleaf`, `moonleaf.app` at the root) and writes its `sha256`. |
| `notarize.sh` | `notarytool submit [--wait\|--no-wait]`, then `stapler staple`, `stapler validate`, and a Gatekeeper assessment of the image. |
| `generate-appcast.sh` | Writes the Sparkle appcast and verifies its enclosure signature before returning. |
| `verify-release.sh` | Fail-closed check of a staged release: checksum, appcast metadata, Ed25519 signature, and the version inside the mounted image. |
| `generate-cask.sh` / `generate-sparkle-keys.sh` | Homebrew cask generation / one-time Ed25519 key pair creation. |

The workflow reads these repository secrets: `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_NOTARIZATION_APPLE_ID`, `APPLE_NOTARIZATION_TEAM_ID`, `APPLE_NOTARIZATION_APP_PASSWORD`, and `SPARKLE_ED_PRIVATE_KEY`. `notarize.sh` also accepts a local Keychain profile instead (`MP_NOTARY_KEYCHAIN_PROFILE`, created with `xcrun notarytool store-credentials`).

## Local dry run

Signing and notarizing the image rewrite `moonleaf.dmg`, so the checksum must be recorded after them, exactly as the workflow does:

```bash
scripts/build.sh --all --yes
MP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/sign_app.sh
scripts/package_dmg.sh build/moonleaf.app dist/moonleaf.dmg
codesign --force --sign "$MP_SIGN_IDENTITY" --timestamp dist/moonleaf.dmg
MP_NOTARY_KEYCHAIN_PROFILE=moonleaf scripts/notarize.sh submit dist/moonleaf.dmg --wait
MP_NOTARY_KEYCHAIN_PROFILE=moonleaf scripts/notarize.sh staple dist/moonleaf.dmg
( cd dist && shasum -a 256 moonleaf.dmg > moonleaf.dmg.sha256 )
scripts/generate-appcast.sh --tag v4.1.0.beta.1 --dmg dist/moonleaf.dmg --output dist/appcast.xml
scripts/verify-release.sh --appcast dist/appcast.xml --dmg dist/moonleaf.dmg \
  --short 4.1.0.beta.1 --build 4010011 --tag v4.1.0.beta.1
```
