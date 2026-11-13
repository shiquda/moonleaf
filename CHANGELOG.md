# Changelog

All notable changes to **Moonleaf** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Wallpapers are applied to a desktop, which is one display plus one Space, instead of one overlay across every Space.
- Usage history keeps the latest 1000 successful applies, with a recent view and a timeline.
- The menu bar can switch the current desktop to a playlist.
- The library can search by name and add a selection to a playlist without changing what is playing.
- Discover saves a chosen file into the library. Pexels video quality is chosen before saving.
- The overview page can shuffle every desktop from the header, or one desktop from its card, without turning rotation on or off.
- The asset detail image opens the preview on a double-click, and shows a preview button while the pointer is over it. The path row copies the image itself.

### Changed
- Separate wallpapers per desktop cannot be turned off.
- New downloads use the current library folder. A future save folder applies only to later downloads.
- The overview shuffle-all button changes every desktop immediately, without a confirmation.


### Fixed
- Switching Spaces refreshes the current desktop before a menu or apply, and a still is not painted onto the visible Space unless that Space is the target.
- A playlist add no longer re-enters the catalog queue.
- Video and GIF history, sessions, and playlist checks update only after the engine reports the same request, path, and time. A failed bind pauses the player.
- Each playlist rotates on its own interval even when library shuffle is off.
- Each desktop keeps its own unconfirmed video request. Clearing a desktop or applying a new wallpaper invalidates the old request, so a late engine report cannot restore it.
- A failed Space lookup pauses and hides a player that was already open.
- A failed bind republishes the last committed wallpaper, so the engine no longer retries the rejected one.
- A one-shot library shuffle keeps the nil or library source, so turning library rotation off still stops that desktop.
- An unconfirmed video shuffle is not reported as changed. The final note names each desktop after the engine replies.
- A video shuffle no longer stays on "waiting" after its receipt arrives while the next desktop is still being applied.
- The asset detail preview covers the manager window, the same full-window preview used by Discover and Library.
- Icon buttons show their action in a tooltip while the pointer is over them.

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
