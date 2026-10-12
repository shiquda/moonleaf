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

moonleaf updates itself with [Sparkle](https://sparkle-project.org). Checks run automatically and can be turned off in **Settings → General → Updates**, which also offers *Check for Updates*, an *Update Log*, and an **Update Server** field.

## 🉑️ Languages

moonleaf is localized in 14 languages — `de`, `en`, `es`, `fr`, `hi`, `it`, `ja`, `ko`, `pl`, `pt-BR`, `ru`, `sk`, `zh-Hans`, `zh-Hant` — and follows your macOS system locale automatically (there is no in-app language picker).

Translation corrections and new languages are welcome via pull request: update or add `lang/<locale>.lproj/Localizable.strings` (source of truth: [`lang/en.lproj/Localizable.strings`](./lang/en.lproj/Localizable.strings), translator template: [`lang/template`](./lang/template)), and optionally add a `credit` file with your GitHub profile URL.

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

## License

moonleaf is licensed under the [MIT License](./LICENSE). Originally created by [naomisphere](https://github.com/illufied).  
Versions prior to v3.0 (`macpaper`) are licensed under the GNU General Public License v3.0 (GPLv3).

## 🤝 Credits & Thanks

- [naomisphere](https://github.com/illufied) — original author of [`illufied/moonleaf`](https://github.com/illufied/moonleaf) ([Ko-fi](https://ko-fi.com/naomisphere))
- Community translators: [@iankyy](https://github.com/iankyy) (`pt-BR`), [@playagain96](https://github.com/playagain96) (`pl`), [@WonTeu](https://github.com/WonTeu) (`sk`)
- [Boring Notch](https://github.com/TheBoredTeam/boring.notch), for README inspiration
- [This Stack Overflow post](https://stackoverflow.com/questions/34215527/what-does-launchd-status-78-mean-why-my-user-agent-not-running), for explaining `launchd` status 78
