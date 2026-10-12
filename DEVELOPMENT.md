# Development

## Building

- `scripts/build.sh` — build for the host architecture (`arm64` or `x86_64`).
- `scripts/build.sh --all --yes` — build a universal binary without the interactive confirmation.

Sparkle is fetched from its official release archive (digest-pinned in `fetch-sparkle.sh`) into `.build/` on the first build, so building needs network access.

## Runtime ownership

- `macpaperService.shared` owns library selection, filters, volume and rotation state. Views and the status menu use the same instance.
- `MoonleafConfig.swift` is compiled into both moonleaf and glasswp. It provides the typed settings model and serialized config access under `~/.config/moonleaf`; the library remains under `~/.local/share/paper/wallpaper`.
- Legacy configuration is migrated once without deleting the original data. The app and engine share an on-disk completion marker and an interprocess migration lock; old preferences migration flags remain valid. Known config symlinks are replaced atomically; unknown JSON fields survive settings updates.
- Startup file reads and service persistence run off the main thread. Volume writes are coalesced over 150 ms.
- `GlasswpProcessManager` starts and adopts verified engine processes and stops them by PID, rather than shell substring matching.
- `AutoStartManager` is the single registration owner for login startup and wallpaper persistence. macOS 13+ uses the signed, bundled LaunchAgent through `SMAppService`; macOS 12 retains the legacy registration path.
- A legacy login job that launched the current app is left intact until a later manual launch can safely migrate it. Disabling removes its plist without terminating the app; re-enabling during that session restores the plist. Bundles with a different identifier cannot manage the production login item. Registered items awaiting macOS approval retain the existing requested-on semantics; logout/reboot and approval require separate session verification.
- `ManagerApp.swift` contains the manager view. Cards, inspector, thumbnails/cache, crop editor, export and browse providers are separate files. Local and remote caches share an implementation but retain independent budgets and size-scoped thumbnail keys.

The obsolete `moonleaf-bin` C helper, shell updater and unbundled screensaver implementation are no longer built or shipped. Updates use Sparkle.

## Refactor smoke checks

Use a disposable app bundle and a fixture home (`open -n --env CFFIXED_USER_HOME=<fixture-home> <app>`); back up the library, config and preferences before testing migrations. Changing the bundle identifier alone does not isolate distributed wallpaper notifications or launchd labels. Do not toggle the fixture's login registration against the production agent.

- Build both architectures with `scripts/build.sh --all --yes`, then verify the signed bundle.
- Exercise library filters, local/remote previews, all settings tabs and status-menu thumbnails.
- Verify file/folder import and original/cropped export against temporary media.
- Verify config migration from real legacy files and symlinks, partial settings, unknown-field preservation and coalesced volume writes.
- Verify engine start, adoption after app relaunch, unset and restart; verify rotation while no manager window is open.
- Validate login registration and migration separately in a disposable macOS account; logout/reboot and multi-Space behavior require an actual session test.

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
