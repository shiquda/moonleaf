//
//  macpaper.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import SwiftUI
import AppKit

@main
struct macpaper: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Settings") {
            SettingsView()
                .environmentObject(macpaperService.shared)
                .frame(minWidth: 550, idealWidth: 600, minHeight: 500, idealHeight: 550)
                .font(Font(font_loader.regular(size: 13)))
        }
        .windowStyle(DefaultWindowStyle())
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var status_item: NSStatusItem?
    var _mwin: NSWindow?
    var _settingsWin: NSWindow?
    @AppStorage("checkForUpdates") private var checkForUpdates = true
    @AppStorage("glassBackground") private var glassBackground = false
    var updater = Updater.shared
    private let service = macpaperService.shared
    static func updateActivationPolicy() {
        let showInDock = UserDefaults.standard.bool(forKey: "showInDock")
        let targetPolicy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        if NSApp.activationPolicy() != targetPolicy {
            NSApp.setActivationPolicy(targetPolicy)
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier {
            let myPID = ProcessInfo.processInfo.processIdentifier
            let alreadyRunning = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .contains { $0.processIdentifier != myPID && !$0.isTerminated }
            if alreadyRunning {
                NSApp.terminate(nil)
                return
            }
        }

        Self.updateActivationPolicy()
        NSApp.windows.forEach { $0.close() }
        
        font_loader.regFonts()
        
        performFirstLaunchMigration()
        service.fetch_wallpapers()
        make_paper_sb_item()

        updater.automaticallyChecksForUpdates = checkForUpdates

        service.launchGlasswpDaemon()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displaysDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// A screen can be plugged in at any moment, and the desktops it brings
    /// have no picture of their own until something decorates them: without
    /// this they stay on the system default.
    @objc private func displaysDidChange() {
        service.refreshScreenCount()
        macpaperService.restoreWallpapersAfterDisplayChange()
    }

    private func performFirstLaunchMigration() {
        MoonleafConfigStore.shared.migrateIfNeededAsync()
        AutoStartManager.migrateLegacyIfNeededAsync()
    }
    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            show_manager()
            return true
        }
        return false
    }

    func make_paper_sb_item() {
        status_item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = status_item?.button {
            if let resourcePath = Bundle.main.path(forResource: "StatusBarIcon", ofType: "png"),
               let iconImage = NSImage(contentsOfFile: resourcePath) {
                iconImage.size = NSSize(width: 18, height: 18)
                iconImage.isTemplate = false
                button.image = iconImage
            } else {
                button.image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "moonleaf")
            }
        }

        status_item?.menu = sb_item_menu()
    }

    @objc func show_manager() {
        if _mwin == nil {
            let contentView = ContentView().environmentObject(service)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )

            window.isReleasedWhenClosed = false
            window.center()
            window.title = "moonleaf"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.hasShadow = true

            let useGlass = glassBackground

            if useGlass {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.contentView = NSHostingView(rootView: contentView.font(Font(font_loader.regular(size: 13))).ignoresSafeArea())
                window.contentView?.wantsLayer = true
                window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
            } else {
                window.isOpaque = true
                window.backgroundColor = NSColor(srgbRed: 0.08, green: 0.10, blue: 0.18, alpha: 0.95)
                window.contentView = NSHostingView(rootView: contentView.font(Font(font_loader.regular(size: 13))))
            }

            window.minSize = NSSize(width: 900, height: 600)
            window.delegate = self
            _mwin = window
        }

        _mwin?.makeKeyAndOrderFront(nil)
        Self.updateActivationPolicy()
        NSApp.activate(ignoringOtherApps: true)
    }
    func sb_item_menu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        populateStatusMenu(menu)
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populateStatusMenu(menu)
    }

    private func populateStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        if service.wallpapers.isEmpty && !service.isLoading {
            service.fetch_wallpapers()
        }

        let currentPath = service.current_wp ?? MoonleafConfigStore.shared.readCurrentWallpaper()
        let wallpaperIsSet = currentPath.map { FileManager.default.fileExists(atPath: $0) } ?? false
        let wallpapers = service.wallpapers.filter { !$0.isFolder }

        let openItem = NSMenuItem(title: NSLocalizedString("sb_open_mgr", comment: "Open Manager"), action: #selector(show_manager), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(NSMenuItem.separator())

        if !wallpapers.isEmpty {
            let wpSubmenu = NSMenu()
            let thumbSize = NSSize(width: 20, height: 14)

            for wallpaper in wallpapers.prefix(8) {
                let item = NSMenuItem(title: wallpaper.name, action: #selector(apply_wp(_:)), keyEquivalent: "")
                item.representedObject = wallpaper
                item.target = self

                if let cached = ImageCache.shared.cachedThumbnail(forPath: wallpaper.path, size: thumbSize) {
                    item.image = cached
                } else {
                    ImageCache.shared.loadThumbnail(forPath: wallpaper.path, size: thumbSize) { img in
                        item.image = img
                    }
                }

                if let activePath = currentPath, activePath == wallpaper.path {
                    item.state = .on
                }
                wpSubmenu.addItem(item)
            }

            if wallpapers.count > 8 {
                wpSubmenu.addItem(NSMenuItem.separator())
                let showAllItem = NSMenuItem(title: NSLocalizedString("sb_show_all", comment: "Show All..."), action: #selector(show_manager), keyEquivalent: "")
                showAllItem.target = self
                wpSubmenu.addItem(showAllItem)
            }

            let wpMenuItem = NSMenuItem(title: NSLocalizedString("sb_wallpapers", comment: "Wallpapers"), action: nil, keyEquivalent: "")
            wpMenuItem.submenu = wpSubmenu
            menu.addItem(wpMenuItem)
        } else {
            let noWpItem = NSMenuItem(title: NSLocalizedString("sb_no_wallpapers", comment: "No wallpapers found"), action: nil, keyEquivalent: "")
            noWpItem.isEnabled = false
            menu.addItem(noWpItem)
        }

        let shuffleItem = NSMenuItem(title: NSLocalizedString("sb_shuffle_now", comment: "Shuffle Now"), action: #selector(shuffle_now), keyEquivalent: "")
        shuffleItem.target = self
        shuffleItem.isEnabled = !wallpapers.isEmpty
        menu.addItem(shuffleItem)

        menu.addItem(NSMenuItem.separator())

        let volumeItem = NSMenuItem()
        let volumeView = NSHostingView(rootView: VolumeSlider(service: service, style: .menu))
        volumeView.frame = NSRect(x: 0, y: 0, width: 200, height: 30)
        volumeItem.view = volumeView
        menu.addItem(volumeItem)
        menu.addItem(NSMenuItem.separator())

        let persistItem = NSMenuItem(title: NSLocalizedString("sb_perst_tooltip", comment: "Auto-start wallpaper"), action: #selector(toggle_launchAgent), keyEquivalent: "")
        persistItem.target = self
        persistItem.state = service.wp_is_agent ? .on : .off
        menu.addItem(persistItem)

        if wallpaperIsSet {
            let unsetItem = NSMenuItem(title: NSLocalizedString("sb_unset_wp", comment: "Unset Wallpaper"), action: #selector(unset_wp), keyEquivalent: "")
            unsetItem.target = self
            menu.addItem(unsetItem)
        }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: NSLocalizedString("sb_settings", comment: "Settings"), action: #selector(show_settings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let checkUpdatesItem = NSMenuItem(title: NSLocalizedString("settings_check_updates", comment: "Check for Updates"), action: #selector(check_for_updates), keyEquivalent: "")
        checkUpdatesItem.target = self
        menu.addItem(checkUpdatesItem)

        let aboutItem = NSMenuItem(title: NSLocalizedString("sb_about", comment: "About moonleaf"), action: #selector(show_about), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: NSLocalizedString("sb_quit", comment: "Quit moonleaf"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    @objc func apply_wp(_ sender: NSMenuItem) {
        guard let wallpaper = sender.representedObject as? endup_wp else { return }
        service.set_wp(wallpaper)
    }

    @objc func shuffle_now() {
        macpaperService.shuffleNow()
    }

    @objc func toggle_launchAgent() {
        service.wp_doPersist(!service.wp_is_agent)
    }

    @objc func unset_wp() {
        service.unset_wp()
    }
    @objc func show_settings() {
        if let existing = _settingsWin {
            Self.updateActivationPolicy()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView().environmentObject(service)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        if let managerWindow = _mwin {
            let mf = managerWindow.frame
            let sf = window.frame.size
            window.setFrameOrigin(NSPoint(x: mf.midX - sf.width / 2, y: mf.midY - sf.height / 2))
        } else {
            window.center()
        }

        window.title = NSLocalizedString("settings", comment: "Settings")
        window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: settingsView.font(Font(font_loader.regular(size: 13))))
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        _settingsWin = window
        Self.updateActivationPolicy()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func check_for_updates() {
        updater.checkForUpdates()
    }

    @objc func show_about() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"

        let alert = NSAlert()
        alert.messageText = "moonleaf"
        alert.informativeText = String(format: NSLocalizedString("sb_about_text", comment: ""), version, build)
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("sb_about_github", comment: "GitHub"))
        alert.addButton(withTitle: NSLocalizedString("sb_about_kofi", comment: "Support on Ko-fi"))
        alert.addButton(withTitle: NSLocalizedString("browse_cancel", comment: "OK"))

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://github.com/shiquda/moonleaf")!)
        } else if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://ko-fi.com/shiquda")!)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        let closingWindow = notification.object as? NSWindow
        if closingWindow == _mwin {
            _mwin = nil
        } else if closingWindow == _settingsWin {
            _settingsWin = nil
        }
        
        Self.updateActivationPolicy()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender == _mwin else { return frameSize }
        return NSSize(width: max(frameSize.width, 900), height: max(frameSize.height, 600))
    }
}
