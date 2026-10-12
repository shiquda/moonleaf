<h1 align="center">
  <br>
  <a href="https://github.com/shiquda/moonleaf"><img src="./artwork/png/moonleaf2.png" alt="moonleaf" width="150"></a>
  <br>
  moonleaf
  <br>
</h1>
<p align="center">
  <i>✨ The Wallpaper Manager for macOS</i>
</p>

<p align="center">
  <a title="release" target="_blank" href="https://github.com/shiquda/moonleaf/releases/latest"><img src="https://img.shields.io/github/v/release/shiquda/moonleaf?style=flat&color=blue&include_prereleases" alt="release"></a>
  <img src="https://img.shields.io/badge/macOS-12%2B-2396ED?style=flat&logo=apple&logoColor=white" alt="platform" style="margin-right: 10px;" />
  <a href="./LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-899ce8?logo=opensourceinitiative" alt="license" />
  </a>
</p>

<p align="center">
moonleaf is a feature-packed Wallpaper Manager for macOS, with support for gifs, videos, online wallpaper browsing, multi-monitor wallpapers, exporting, among other many things!
</p>

<h1 align="center">
✨ Preview
</h1>
<p align="center">
  <img src="https://github.com/user-attachments/assets/15118fad-306d-4804-b108-462e81fef237" alt="Demo GIF" />
</p>

> [!NOTE]
> **Maintenance Notice:** Upstream [`illufied/moonleaf`](https://github.com/illufied/moonleaf) (originally created by [naomisphere](https://github.com/illufied), last released as `v4.0.0`) is archived and no longer maintained. This fork ([`shiquda/moonleaf`](https://github.com/shiquda/moonleaf)) is the actively maintained line—continuing development with bug fixes, new features, and new translations—and is the source of all new releases under the original [MIT License](./LICENSE).

---

## Installation

**System Requirements:**
- macOS **12** *(Monterey)* or later
- Apple Silicon (`arm64`) or Intel (`x86_64`) Mac (universal binary)

Download the latest `moonleaf.dmg` from [GitHub Releases](https://github.com/shiquda/moonleaf/releases/latest/download/moonleaf.dmg), open the disk image, and drag `moonleaf.app` to `/Applications`.

<p align="center">
  <a href="https://github.com/shiquda/moonleaf/releases/latest/download/moonleaf.dmg" target="_self"><img width="200" src="https://github.com/user-attachments/assets/e2b187d1-8010-45cf-a9d4-e7ce5e2e677c" alt="Download moonleaf.dmg" /></a>
</p>

## Updates

moonleaf updates itself with [Sparkle](https://sparkle-project.org). Every release publishes a signed `appcast.xml` at `https://github.com/shiquda/moonleaf/releases/latest/download/appcast.xml`; the update archive carries an Ed25519 signature checked against the public key compiled into the app, and each release also publishes its `sha256` for manual verification.

- Automatic update checks are on by default and can be turned off in **Settings → General → Updates**, which also has *Check for Updates*, *Update Log*, and an **Update Server** field that only changes which GitHub repository the checks point at.
- Releases up to `v4.0.0` used the previous hand-rolled updater (a `latest` file plus `moonleaf.dmg`). That path stays published so those older copies can migrate to a Sparkle release.

## 🉑️ Languages

moonleaf is localized in 14 languages. The app follows your macOS system locale automatically (there is no in-app language picker).

| Locale | Language | Bundle Directory | Credit |
| :--- | :--- | :--- | :--- |
| `en` | English | `lang/en.lproj` (`lang/Base.lproj`) | — |
| `de` | Deutsch | `lang/de.lproj` | — |
| `es` | Español | `lang/es.lproj` | — |
| `fr` | Français | `lang/fr.lproj` | — |
| `hi` | हिन्दी | `lang/hi.lproj` | — |
| `it` | Italiano | `lang/it.lproj` | — |
| `ja` | 日本語 | `lang/ja.lproj` | — |
| `ko` | 한국어 | `lang/ko.lproj` | — |
| `pl` | Polski | `lang/pl.lproj` | [@playagain96](https://github.com/playagain96) |
| `pt-BR` | Português (Brasil) | `lang/pt-BR.lproj` | [@iankyy](https://github.com/iankyy) |
| `ru` | Русский | `lang/ru.lproj` | — |
| `sk` | Slovenčina | `lang/sk.lproj` | [@WonTeu](https://github.com/WonTeu) |
| `zh-Hans` | 简体中文 | `lang/zh-Hans.lproj` | — |
| `zh-Hant` | 繁體中文 | `lang/zh-Hant.lproj` | — |

Translation corrections and new languages are welcome via pull request:
- Source of truth: [`lang/en.lproj/Localizable.strings`](./lang/en.lproj/Localizable.strings)
- Translator template: [`lang/template`](./lang/template)
- Update or add `lang/<locale>.lproj/Localizable.strings` (and optionally a `credit` file with your GitHub profile URL).

## 🔨 Building from Source

**Prerequisites:** Xcode Command Line Tools (`swiftc`, `gcc`, `lipo`).

- Build for your host architecture (`arm64` or `x86_64`):
  ```bash
  scripts/build.sh
  ```
- Build a universal binary (`arm64` + `x86_64`) non-interactively (`--yes` skips the confirmation prompt):
  ```bash
  scripts/build.sh --all --yes
  ```
  Sparkle is fetched automatically from its official release archive (digest-checked) into `.build/`, so the first build needs network access.

### Release engineering

[`.github/workflows/release.yml`](./.github/workflows/release.yml) drives these scripts:

| Script | Purpose |
| --- | --- |
| `release-version.sh <tag>` | Turns `v4.1.0.beta.1` into the user-facing version plus a monotonic numeric `CFBundleVersion` that Sparkle compares. |
| `fetch-sparkle.sh` | Downloads the pinned Sparkle release into `.build/` and exports its framework and tool paths. |
| `sign_app.sh` | Re-signs Sparkle's nested code and every helper binary, then the app (Developer ID + hardened runtime; `--adhoc` for local builds). |
| `package_dmg.sh` | Builds `moonleaf.dmg` (volume `moonleaf`, `moonleaf.app` at the root) and writes its `sha256`. |
| `notarize.sh` | `notarytool submit --wait`, then `stapler staple` and `stapler validate`. |
| `generate-appcast.sh` | Writes the Sparkle appcast and verifies its signature before returning. |
| `verify-release.sh` | Fail-closed check of a staged release: checksum, appcast metadata, Ed25519 signature, and the version inside the mounted image. |
| `generate-cask.sh` / `generate-sparkle-keys.sh` | Homebrew cask generation / one-time Ed25519 key pair creation. |

Notarization and appcast signing read these repository secrets: `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_NOTARIZATION_APPLE_ID`, `APPLE_NOTARIZATION_TEAM_ID`, `APPLE_NOTARIZATION_APP_PASSWORD`, and `SPARKLE_ED_PRIVATE_KEY`.

## 🛠️ Troubleshooting

### Quarantine
If you suspect the app is quarantined, run the following in Terminal after dragging the app to `/Applications`:
```bash
xattr -l /Applications/moonleaf.app
```
If the output includes `com.apple.quarantine`, remove it with:
```bash
xattr -dr com.apple.quarantine /Applications/moonleaf.app
```

### Apple could not verify "moonleaf" is free of malware...
This should not happen with a downloaded release. If you compiled the app yourself, allow it under **System Settings → Privacy & Security → Open Anyway**.

## License

moonleaf is licensed under the [MIT License](./LICENSE). Originally created by [naomisphere](https://github.com/illufied).  
Versions prior to v3.0 (`macpaper`) are licensed under the GNU General Public License v3.0 (GPLv3).

## 🤝 Credits & Thanks

- [naomisphere](https://github.com/illufied) — original author of [`illufied/moonleaf`](https://github.com/illufied/moonleaf) ([Ko-fi](https://ko-fi.com/naomisphere))
- Community translators: [@iankyy](https://github.com/iankyy) (`pt-BR`), [@playagain96](https://github.com/playagain96) (`pl`), [@WonTeu](https://github.com/WonTeu) (`sk`)
- [Boring Notch](https://github.com/TheBoredTeam/boring.notch), for README inspiration
- [This Stack Overflow post](https://stackoverflow.com/questions/34215527/what-does-launchd-status-78-mean-why-my-user-agent-not-running), for explaining `launchd` status 78
