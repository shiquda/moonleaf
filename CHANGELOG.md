# Changelog

All notable changes to **Moonleaf** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.1.1] - 2026-10-23

### Added
- **Settings**: Added a "Show in Dock" toggle in Preferences with default set to hidden, allowing users to choose whether to display Moonleaf in the macOS Dock. Localized into 14 languages (`7636e0d`).

### Fixed
- **Window & Focus Management**: Fixed application activation policy when opening folder choosers or exporting wallpapers by centralizing management under `AppDelegate.updateActivationPolicy()`, preventing erratic focus and Dock icon jumps (`7636e0d`).

### Documentation & Distribution
- **Website**: Launched the official GitHub Pages documentation website at [https://shiquda.github.io/moonleaf](https://shiquda.github.io/moonleaf) with responsive showcase, FAQ, and structured SEO metadata.
- **Homebrew**: Modernized Homebrew tap integration (`shiquda/homebrew-moonleaf`) and cask generation script.
- **CI**: Standardized release automation and release note formatting.

## [4.1.0] - 2026-10-15

### Fixed
- **Wallpaper Rotation**: Stopped the per-desktop rotation pool from collapsing onto stale desktops by only querying active virtual desktops (`74efef9`).
- **Startup & Migration**: Preserved login startup across app and engine; coordinated legacy config migration from `macpaper` (`b68041a`, `0f352cd`).
- **Architecture**: Consolidated runtime ownership and decoupled wallpaper UI components (`9a70831`).

### Added
- **Wallpaper Discovery**: Added full-window quick preview for exploring wallpapers (`4e76173`).
- **Auto-Updates**: Added Sparkle automated update channel with notarization and appcast verification.
- **Distribution**: Added official Homebrew cask distribution (`brew install shiquda/moonleaf/moonleaf`).

## [4.0.0] - 2024-03-08

- Final release under upstream `illufied/moonleaf` (formerly `macpaper`), now archived.
