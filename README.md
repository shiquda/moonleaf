<h1 align="center">
  <br>
  <a href="https://github.com/shiquda/moonleaf"><img src="./artwork/png/moonleaf2.png" alt="moonleaf" width="140"></a>
  <br>
  moonleaf
  <br>
</h1>

<p align="center">
  <b>moonleaf – actively maintained fork (formerly macpaper)</b><br>
  <i>✨ The modern, lightweight Wallpaper Manager for macOS</i>
</p>

<p align="center">
  <a title="release" target="_blank" href="https://github.com/shiquda/moonleaf/releases/latest"><img src="https://img.shields.io/github/v/release/shiquda/moonleaf?style=flat&color=blue&include_prereleases" alt="release"></a>
  <img src="https://img.shields.io/badge/macOS-12%2B-2396ED?style=flat&logo=apple&logoColor=white" alt="platform" style="margin-right: 10px;" />
  <a href="https://shiquda.github.io/moonleaf"><img src="https://img.shields.io/badge/Website-shiquda.github.io-58a6ff?logo=safari&logoColor=white" alt="website" /></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-MIT-899ce8?logo=opensourceinitiative" alt="license" /></a>
</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/15118fad-306d-4804-b108-462e81fef237" alt="Moonleaf Demo Preview" width="800" />
</p>

## 📦 Installation

### Via Homebrew (Recommended)

```bash
brew install shiquda/moonleaf/moonleaf
```

*(Or add the tap manually: `brew tap shiquda/moonleaf && brew install --cask moonleaf`)*

### Direct Download

Download the latest `moonleaf.dmg` from [GitHub Releases](https://github.com/shiquda/moonleaf/releases/latest/download/moonleaf.dmg), open the disk image, and drag `moonleaf.app` into `/Applications`.

**System Requirements:**
- macOS **12** *(Monterey)* or later (tested on macOS **26** *Tahoe*)
- Universal binary: native on **Apple Silicon** (`arm64`) and **Intel** (`x86_64`)

---

## 🔄 Upgrading from v4.0.0 (or macpaper)

> [!IMPORTANT]
> **Upstream Maintenance Notice:** Upstream [`illufied/moonleaf`](https://github.com/illufied/moonleaf) (originally created by [naomisphere](https://github.com/illufied), frozen at `v4.0.0`) has been archived. **Its built-in legacy auto-updater no longer receives updates.**  
> This fork ([`shiquda/moonleaf`](https://github.com/shiquda/moonleaf)) is the actively maintained line, providing bug fixes, Sparkle auto-updates, and Homebrew tap distribution. It requires macOS 12 or later; tested on macOS 26 Tahoe.

**Seamless, Non-destructive Upgrade:**
1. Install the latest version via Homebrew (`brew install shiquda/moonleaf/moonleaf`) or download [`moonleaf.dmg`](https://github.com/shiquda/moonleaf/releases/latest/download/moonleaf.dmg).
2. Launch `moonleaf.app`. Your existing wallpaper collection (`~/.local/share/paper/wallpaper`) and configuration (`~/.config/moonleaf`) are **automatically recognized and preserved**. No data is lost.
3. Future updates will be delivered automatically via the built-in Sparkle updater (**Settings → General → Updates**).

---

## ✨ Features

- **Per-Monitor & Space Desktop Overview:** View active monitors and macOS Spaces together, assign and auto-recognize static wallpapers per display and Space, and shuffle all desktops or a single desktop in one click.
- **Named Playlists & Menu Bar Switching:** Group library wallpapers into playlists without duplicating files, set sequential or random rotation with per-list intervals (15 min to daily), and switch the current desktop's playlist from the menu bar.
- **1,000-Item History & Clear Storage:** Track your last 1,000 successful wallpaper changes in Recent and Timeline views, and inspect Library files, External references, and clearable Download cache under Storage settings.
- **Dynamic Video & GIF Wallpapers:** Smooth playback of MP4, MOV, and GIF media with native AppKit and AVFoundation hardware-accelerated rendering.
- **In-App Wallpaper Discovery & Quick Controls:** Browse wallpapers from [Wallhaven](https://wallhaven.cc) and [Pexels](https://pexels.com), open full-window Quick Preview (`Esc` to close), and copy images directly to the clipboard from the detail sheet.
- **Lightweight, Native & Sparkle Auto-Updates:** Pure Swift and AppKit universal binary (`arm64` + `x86_64`) with Apple Developer ID notarization and signed Sparkle updates. We have not published a battery or CPU figure beyond one playback test on an M1 Pro running macOS 26.7.1.

---

## 🔄 In-App Updates

moonleaf updates itself with [Sparkle](https://sparkle-project.org). Checks run automatically and can be configured in **Settings → General → Updates**, which also offers *Check for Updates*, an *Update Log*, and an **Update Server** field.

## 🉑️ Languages

moonleaf is localized in 14 languages — `de`, `en`, `es`, `fr`, `hi`, `it`, `ja`, `ko`, `pl`, `pt-BR`, `ru`, `sk`, `zh-Hans`, `zh-Hant` — and follows your macOS system locale automatically.

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

## 📖 Guides

- [How to Set a Different Wallpaper per Monitor and Space on Mac](https://shiquda.github.io/moonleaf/guides/different-wallpaper-per-monitor-space-mac/)
- [macOS Wallpaper Playlists, Rotation & History (Free Guide)](https://shiquda.github.io/moonleaf/guides/wallpaper-playlists-mac/)
- [How to Set a GIF as Wallpaper on Mac (Free, No Converting)](https://shiquda.github.io/moonleaf/guides/gif-wallpaper-mac/)
- [How to Set a Video as Wallpaper on Mac (Free, MP4 & MOV)](https://shiquda.github.io/moonleaf/guides/video-wallpaper-mac/)

## 🛠️ Troubleshooting

### Quarantine & Gatekeeper
Official releases are signed with an Apple Developer ID and notarized by Apple. macOS Gatekeeper automatically verifies the notarization ticket on first launch. If you build from source or macOS displays a quarantine prompt under custom security policies, right-click `moonleaf.app` in Finder and choose **Open**, or run:
```bash
xattr -dr com.apple.quarantine /Applications/moonleaf.app
```

## 📄 License

moonleaf is licensed under the [MIT License](./LICENSE). Originally created by [naomisphere](https://github.com/illufied).  
Versions prior to v3.0 (`macpaper`) are licensed under the GNU General Public License v3.0 (GPLv3).

## 🤝 Credits & Thanks

- [naomisphere](https://github.com/illufied) — original author of [`illufied/moonleaf`](https://github.com/illufied/moonleaf) ([Ko-fi](https://ko-fi.com/naomisphere))
- Community translators: [@iankyy](https://github.com/iankyy) (`pt-BR`), [@playagain96](https://github.com/playagain96) (`pl`), [@WonTeu](https://github.com/WonTeu) (`sk`)
- [Boring Notch](https://github.com/TheBoredTeam/boring.notch), for README inspiration
- [This Stack Overflow post](https://stackoverflow.com/questions/34215527/what-does-launchd-status-78-mean-why-my-user-agent-not-running), for explaining `launchd` status 78
