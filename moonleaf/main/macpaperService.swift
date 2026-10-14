//
//  macpaperService.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import Foundation
import Combine
import AppKit

class macpaperService: NSObject, ObservableObject {
    static let shared = macpaperService()

    @Published var wallpapers: [endup_wp] = []
    @Published var isLoading = false
    @Published var current_wp: String?
    @Published var volume: Double = 0.5
    @Published var wp_is_agent: Bool = false
    @Published var ap_is_enabled: Bool = false
    @Published var showVideos: Bool = true
    @Published var showImages: Bool = true
    @Published var selected_wp: endup_wp? = nil
    @Published var favorites: Set<String> = []
    @Published var localSort: LocalSortMode = .date
    @Published var shuffleEnabled: Bool = false
    @Published var shuffleInterval: ShuffleInterval = .oneHour
    @Published var perSpaceShuffle: Bool = false
    @Published var importMethod: ImportMethod = .link
    @Published var currentPath: URL?
    @Published var navStack: [URL] = []

    @Published var screenWallpapers: [Int: String] = [:]

    @Published var screenCount: Int = 1

    var isAtRoot: Bool {
        return navStack.isEmpty
    }

    static let wp_storage_dir = MoonleafConfigStore.libraryRoot
    static let settings_file = MoonleafConfigStore.settingsFile

    private let wp_storage_dir = macpaperService.wp_storage_dir
    private static var shuffleLoop: DispatchSourceTimer?
    private var didMutateSettingsBeforeInitialLoad = false
    private var didMutateVolumeBeforeInitialLoad = false
    private var didMutateWallpaperBeforeInitialLoad = false
    enum LocalSortMode: String, CaseIterable {
        case date = "date"
        case name = "name"
        case size = "size"

        var displayName: String {
            switch self {
            case .date: return NSLocalizedString("sort_by_date", comment: "Date Added")
            case .name: return NSLocalizedString("sort_by_name", comment: "Name")
            case .size: return NSLocalizedString("sort_by_size", comment: "File Size")
            }
        }
    }

    enum ShuffleInterval: String, CaseIterable {
        case fifteenMin = "15min"
        case oneHour = "1hr"
        case threeHour = "3hr"
        case daily = "daily"

        var displayName: String {
            switch self {
            case .fifteenMin: return NSLocalizedString("shuffle_interval_15min", comment: "15 minutes")
            case .oneHour: return NSLocalizedString("shuffle_interval_1hr", comment: "1 hour")
            case .threeHour: return NSLocalizedString("shuffle_interval_3hr", comment: "3 hours")
            case .daily: return NSLocalizedString("shuffle_interval_daily", comment: "Daily")
            }
        }

        var seconds: Double {
            switch self {
            case .fifteenMin: return 15 * 60
            case .oneHour: return 60 * 60
            case .threeHour: return 3 * 60 * 60
            case .daily: return 24 * 60 * 60
            }
        }
    }

    enum ImportMethod: String, CaseIterable {
        case copy = "copy"
        case link = "link"
    }

    override init() {
        super.init()
        loadInMemoryDefaults()
        screenCount = NSScreen.screens.count
        macpaperService.syncShuffleLoop()
        loadInitialConfigAsync()
    }

    public func launchGlasswpDaemon() {
        let perDesktop = UserDefaults.standard.bool(forKey: macpaperService.perSpaceShuffleKey)
        GlasswpProcessManager.shared.ensureRunning(perDesktopMode: perDesktop)
    }

    func select_wp(_ wallpaper: endup_wp?) {
        selected_wp = wallpaper
    }

    func toggleFavorite(_ wallpaper: endup_wp) {
        if favorites.contains(wallpaper.path) {
            favorites.remove(wallpaper.path)
        } else {
            favorites.insert(wallpaper.path)
        }
        saveFavorites()
    }

    func isFavorite(_ wallpaper: endup_wp) -> Bool {
        return favorites.contains(wallpaper.path)
    }

    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: "moonleaf_favorites"),
           let paths = try? JSONDecoder().decode([String].self, from: data) {
            favorites = Set(paths)
        }
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(Array(favorites)) {
            UserDefaults.standard.set(data, forKey: "moonleaf_favorites")
        }
    }

    func setLocalSort(_ mode: LocalSortMode) {
        localSort = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "moonleaf_localSort")
        applyLocalSort()
    }

    private func applyLocalSort() {
        switch localSort {
        case .date:
            wallpapers = wallpapers.sorted { $0.createdDate > $1.createdDate }
        case .name:
            wallpapers = wallpapers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size:
            wallpapers = wallpapers.sorted { $0.fileSize > $1.fileSize }
        }
    }

    func setShuffleEnabled(_ enabled: Bool) {
        shuffleEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: macpaperService.shuffleEnabledKey)
        macpaperService.syncShuffleLoop()
    }

    func setShuffleInterval(_ interval: ShuffleInterval) {
        shuffleInterval = interval
        UserDefaults.standard.set(interval.rawValue, forKey: macpaperService.shuffleIntervalKey)
        if shuffleEnabled {
            macpaperService.restartShuffleLoop()
        }
    }

    private static let shuffleEnabledKey = "moonleaf_shuffleEnabled"
    private static let shuffleIntervalKey = "moonleaf_shuffleInterval"
    private static let perSpaceShuffleKey = "moonleaf_perSpaceShuffle"
    private static let lastShuffleKey = "moonleaf_lastShuffle"

    /// Turns the per-desktop rotation on or off. Switching it on applies it
    /// right away, otherwise nothing would happen until the next interval.
    func setPerSpaceShuffle(_ enabled: Bool) {
        perSpaceShuffle = enabled
        UserDefaults.standard.set(enabled, forKey: macpaperService.perSpaceShuffleKey)
        macpaperService.postPerDesktopMode(enabled)
        if enabled && shuffleEnabled {
            macpaperService.rotateDesktops()
        } else if !enabled, let path = current_wp ?? UserDefaults.standard.string(forKey: macpaperService.lastShuffleKey) {
            // The overlay engine stopped drawing while the desktops had pictures
            // of their own, so hand it the current wallpaper back right away.
            postOverlayNotification(path: path)
        }
    }

    /// The overlay engine keeps one picture for every desktop, so it has to
    /// step aside while the desktops have pictures of their own.
    static func postPerDesktopMode(_ enabled: Bool) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.naomisphere.moonleaf.perDesktopMode"),
            object: nil,
            userInfo: ["enabled": enabled],
            deliverImmediately: true
        )
    }

    /// Arms the rotation loop when the setting is on and no loop is running yet.
    ///
    /// The loop is deliberately process-wide: every window, menu and settings
    /// pane builds its own short-lived `macpaperService`, so an instance-owned
    /// timer dies with whatever window happened to create it.
    static func syncShuffleLoop() {
        let enabled = UserDefaults.standard.bool(forKey: shuffleEnabledKey)
        guard enabled else {
            shuffleLoop?.cancel()
            shuffleLoop = nil
            return
        }
        guard shuffleLoop == nil else { return }
        let intervalRaw = UserDefaults.standard.string(forKey: shuffleIntervalKey)
        let interval = intervalRaw.flatMap(ShuffleInterval.init(rawValue:)) ?? .oneHour
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
        timer.schedule(deadline: .now() + interval.seconds, repeating: interval.seconds)
        timer.setEventHandler { macpaperService.shuffleTick() }
        timer.resume()
        shuffleLoop = timer
    }

    private static func restartShuffleLoop() {
        shuffleLoop?.cancel()
        shuffleLoop = nil
        syncShuffleLoop()
    }

    /// Rotates to a library wallpaper right now, on demand from the status menu.
    /// When the rotation loop is armed its interval starts over, so a manual
    /// pick is not followed by an automatic one seconds later.
    static func shuffleNow() {
        DispatchQueue.global(qos: .userInitiated).async {
            shuffleTick()
            if shuffleLoop != nil {
                restartShuffleLoop()
            }
        }
    }

    private static func shuffleTick() {
        let candidates = library_candidates()
        guard !candidates.isEmpty else { return }

        if UserDefaults.standard.bool(forKey: perSpaceShuffleKey) {
            rotateDesktops(candidates)
            return
        }

        guard let next = random_library_wallpaper(from: candidates) else { return }
        DispatchQueue.main.async {
            macpaperService.shared.set_wp(next)
        }
    }

    /// Still images and videos in the library root that the Show Images/Videos
    /// settings keep visible; folders are skipped, they are not settable.
    private static func library_candidates() -> [endup_wp] {
        let settings = MoonleafConfigStore.shared.loadSettings()
        return scan_library(wp_storage_dir).filter {
            !$0.isFolder && is_visible($0, showImages: settings.showImages, showVideos: settings.showVideos)
        }
    }

    /// Never returns the file that was used for the previous rotation.
    private static func random_library_wallpaper(from candidates: [endup_wp]) -> endup_wp? {
        guard candidates.count > 1 else { return candidates.first }

        let previous = UserDefaults.standard.string(forKey: lastShuffleKey)
        let pool = candidates.filter { $0.path != previous }
        guard let next = (pool.isEmpty ? candidates : pool).randomElement() else { return nil }
        UserDefaults.standard.set(next.path, forKey: lastShuffleKey)
        return next
    }

    /// Gives every desktop its own wallpaper.
    ///
    /// Desktops rotate: a desktop never keeps the image it shows right now, and
    /// images that are on a desktop already are picked last, so the library
    /// cycles through the desktops instead of repeating.
    static func rotateDesktops() {
        rotateDesktops(library_candidates())
    }

    private static func rotateDesktops(_ candidates: [endup_wp]) {
        let stills = candidates.filter {
            ["jpg", "jpeg", "png"].contains(($0.path as NSString).pathExtension.lowercased())
        }
        let spaces = SpaceWallpapers.liveSpaces()
        guard !stills.isEmpty, !spaces.isEmpty else { return }

        let current = SpaceWallpapers.liveAssignments(for: spaces)
        let onScreen = Set(current.values)
        var claimed = Set<String>()
        var assignment: [SpaceWallpapers.Space: String] = [:]

        for space in spaces {
            let previous = current[space.uuid]
            let unused = stills.filter {
                !onScreen.contains($0.path) && !claimed.contains($0.path) && $0.path != previous
            }
            let fresh = stills.filter { !claimed.contains($0.path) && $0.path != previous }
            let remaining = stills.filter { !claimed.contains($0.path) }
            let pool = !unused.isEmpty ? unused : (!fresh.isEmpty ? fresh : (!remaining.isEmpty ? remaining : stills))
            guard let pick = pool.randomElement() else { continue }
            claimed.insert(pick.path)
            assignment[space] = pick.path
        }
        guard !assignment.isEmpty else { return }
        guard SpaceWallpapers.assign(assignment) else { return }

        // WallpaperAgent keeps the desktops in memory and only re-reads the
        // store when it starts or when a desktop is switched to, so it is
        // restarted here: that is what makes every desktop show its new
        // wallpaper now instead of only the ones visited next.
        SpaceWallpapers.reload()

        if let visible = spaces.first(where: { $0.isCurrent }), let path = assignment[visible] {
            macpaperService.shared.mark_current_wallpaper(path)
        }
    }

    func _ap_enabled(_ enabled: Bool) {
        ap_is_enabled = enabled
        saveSettings()

        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.naomisphere.moonleaf.autoPauseChanged"),
            object: nil,
            userInfo: ["ap_is_enabled": enabled],
            deliverImmediately: true
        )
    }

    /// Restores wallpapers after the display layout changed.
    ///
    /// A screen that was just plugged in comes online with desktops that have no
    /// picture of their own, and those fall back to the system default until
    /// something decorates them: under the per-desktop rotation they are filled
    /// from the library, otherwise they are handed the picture the other
    /// desktops already show.
    static func restoreWallpapersAfterDisplayChange() {
        // A screen settling in reports the change several times, and every pass
        // reads and writes the same store, so they are run one after another.
        displayChangeQueue.async {
            let spaces = SpaceWallpapers.liveSpaces()
            guard !spaces.isEmpty else { return }

            let current = SpaceWallpapers.liveAssignments(for: spaces)
            let missing = spaces.filter { current[$0.uuid] == nil }
            guard !missing.isEmpty else { return }

            guard UserDefaults.standard.bool(forKey: perSpaceShuffleKey) else {
                guard let path = UserDefaults.standard.string(forKey: lastShuffleKey) ?? current.values.sorted().first,
                      FileManager.default.fileExists(atPath: path) else { return }
                DispatchQueue.main.async { macpaperService.shared.set_wp_path(path) }
                return
            }

            let stills = library_candidates().filter {
                ["jpg", "jpeg", "png"].contains(($0.path as NSString).pathExtension.lowercased())
            }
            guard !stills.isEmpty else { return }

            var claimed = Set(current.values)
            var assignment: [SpaceWallpapers.Space: String] = [:]
            for space in missing {
                let unclaimed = stills.filter { !claimed.contains($0.path) }
                guard let pick = (unclaimed.isEmpty ? stills : unclaimed).randomElement() else { continue }
                claimed.insert(pick.path)
                assignment[space] = pick.path
            }
            guard !assignment.isEmpty, SpaceWallpapers.assign(assignment) else { return }
            SpaceWallpapers.reload()
        }
    }

    private static let displayChangeQueue = DispatchQueue(label: "com.naomisphere.moonleaf.displayChange")

    /// Applies an already chosen picture, without going through the wallpaper
    /// picker's per-desktop pinning.
    func set_wp_path(_ path: String) {
        didMutateWallpaperBeforeInitialLoad = true
        MoonleafConfigStore.shared.writeCurrentWallpaperAsync(path)
        _exec_wallpaper(["set", path]) { _ in }
        GlasswpProcessManager.shared.ensureRunning(perDesktopMode: perSpaceShuffle)
        postOverlayNotification(path: path)
    }

    private func loadInMemoryDefaults() {
        currentPath = wp_storage_dir
        wp_is_agent = UserDefaults.standard.bool(forKey: "autoStartEnabled")

        loadFavorites()

        if let sortRaw = UserDefaults.standard.string(forKey: "moonleaf_localSort"),
           let sort = LocalSortMode(rawValue: sortRaw) {
            localSort = sort
        }

        shuffleEnabled = UserDefaults.standard.bool(forKey: "moonleaf_shuffleEnabled")
        perSpaceShuffle = UserDefaults.standard.bool(forKey: "moonleaf_perSpaceShuffle")

        if let intervalRaw = UserDefaults.standard.string(forKey: "moonleaf_shuffleInterval"),
           let interval = ShuffleInterval(rawValue: intervalRaw) {
            shuffleInterval = interval
        }
    }

    private func loadInitialConfigAsync() {
        MoonleafConfigStore.shared.loadStartupSnapshotAsync { [weak self] snapshot in
            guard let self = self else { return }

            if !self.didMutateSettingsBeforeInitialLoad {
                let prevShowVideos = self.showVideos
                let prevShowImages = self.showImages
                self.ap_is_enabled = snapshot.settings.ap_is_enabled
                self.showVideos = snapshot.settings.showVideos
                self.showImages = snapshot.settings.showImages
                if let method = ImportMethod(rawValue: snapshot.settings.import_method) {
                    self.importMethod = method
                }
                if (prevShowVideos != self.showVideos || prevShowImages != self.showImages) && !self.wallpapers.isEmpty {
                    self.fetch_wallpapers()
                }
            }

            if !self.didMutateVolumeBeforeInitialLoad {
                self.volume = snapshot.volume
            }

            if !self.didMutateWallpaperBeforeInitialLoad {
                self.current_wp = snapshot.currentWallpaper
                if !snapshot.screenWallpapers.isEmpty {
                    self.screenWallpapers = snapshot.screenWallpapers
                    let loaded = snapshot.screenWallpapers
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        for (idx, path) in loaded {
                            guard FileManager.default.fileExists(atPath: path) else { continue }
                            DistributedNotificationCenter.default().postNotificationName(
                                Notification.Name("com.naomisphere.moonleaf.changeWallpaper"),
                                object: nil,
                                userInfo: ["filePath": path, "screenIndex": idx],
                                deliverImmediately: true
                            )
                        }
                    }
                }
            }
        }
    }

    func saveSettings() {
        didMutateSettingsBeforeInitialLoad = true
        let apEnabled = ap_is_enabled
        let videos = showVideos
        let images = showImages
        let methodRaw = importMethod.rawValue
        MoonleafConfigStore.shared.updateSettingsAsync { settings in
            settings.ap_is_enabled = apEnabled
            settings.showVideos = videos
            settings.showImages = images
            settings.import_method = methodRaw
        }
    }

    func chvol(_ new_vol: Double) {
        didMutateVolumeBeforeInitialLoad = true
        let clamped = max(0.0, min(1.0, new_vol))
        volume = clamped
        let volumeFloat = Float(clamped)

        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.naomisphere.moonleaf.volumeChanged"),
            object: nil,
            userInfo: ["volume": volumeFloat],
            deliverImmediately: true
        )

        MoonleafConfigStore.shared.writeVolumeThrottled(clamped)
    }

    /// Lists every folder and media file directly inside `directory`, unsorted
    /// and unfiltered; callers decide what to keep visible.
    static func scan_library(_ directory: URL) -> [endup_wp] {
        let scanPath = directory.resolvingSymlinksInPath()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: scanPath,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]) else {
            return []
        }

        let validExts = ["mov", "mp4", "gif", "jpg", "jpeg", "png"]
        return files.compactMap { url -> endup_wp? in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
            let isFolder = isDir.boolValue
            if !isFolder && !validExts.contains(url.pathExtension.lowercased()) { return nil }

            let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let modDate = rv?.contentModificationDate
                ?? (attrs?[.modificationDate] as? Date)
                ?? Date.distantPast
            let fileSize = rv?.fileSize.map(Int64.init)
                ?? (attrs?[.size] as? Int64)
                ?? 0

            return endup_wp(
                id: UUID(),
                name: url.deletingPathExtension().lastPathComponent,
                path: url.path,
                preview: nil,
                createdDate: modDate,
                fileSize: fileSize,
                isFolder: isFolder
            )
        }
    }

    static func is_visible(_ wallpaper: endup_wp, showImages: Bool, showVideos: Bool) -> Bool {
        let ext = (wallpaper.path as NSString).pathExtension.lowercased()
        if !showVideos && ["mov", "mp4", "gif"].contains(ext) { return false }
        if !showImages && !wallpaper.isFolder && ["jpg", "jpeg", "png"].contains(ext) { return false }
        return true
    }

    func fetch_wallpapers() {
        isLoading = true

        try? FileManager.default.createDirectory(at: wp_storage_dir, withIntermediateDirectories: true)
        let scanPath = currentPath ?? wp_storage_dir

        DispatchQueue.global(qos: .background).async { [weak self] in
            let items = macpaperService.scan_library(scanPath)

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.wallpapers = items.filter {
                    macpaperService.is_visible($0, showImages: self.showImages, showVideos: self.showVideos)
                }
                self.applyLocalSort()
                self.isLoading = false
            }
        }
    }

    func set_wp(_ wallpaper: endup_wp) {
        let ext = (wallpaper.path as NSString).pathExtension.lowercased()
        let isMoving = ["mov", "mp4", "gif"].contains(ext)
        let isStill = ["jpg", "jpeg", "png"].contains(ext)

        guard isMoving || isStill else { return }

        if isMoving && perSpaceShuffle {
            // An animated wallpaper is drawn by the overlay engine across every
            // desktop, so it cannot live next to the per-desktop rotation.
            setPerSpaceShuffle(false)
        }

        didMutateWallpaperBeforeInitialLoad = true
        DispatchQueue.main.async { self.selected_wp = wallpaper }

        MoonleafConfigStore.shared.writeCurrentWallpaperAsync(wallpaper.path)
        MoonleafConfigStore.shared.writeScreenWallpapersAsync([:])
        GlasswpProcessManager.shared.ensureRunning(perDesktopMode: perSpaceShuffle)
        if isStill {
            let cliPath = Bundle.main.bundlePath + "/Contents/Resources/bin/wallpaper"
            if FileManager.default.fileExists(atPath: cliPath) {
                _exec_wallpaper(["set", wallpaper.path]) { [weak self] _ in
                    guard let self = self else { return }
                    self.pin_to_current_desktop(wallpaper.path)
                    self.postOverlayNotification(path: wallpaper.path)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.current_wp = wallpaper.path
                        self.screenWallpapers.removeAll()
                        self.saveScreenWallpapers()
                    }
                }
            } else {
                self.pin_to_current_desktop(wallpaper.path)
                self.postOverlayNotification(path: wallpaper.path)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.current_wp = wallpaper.path
                    self.screenWallpapers.removeAll()
                    self.saveScreenWallpapers()
                }
            }
            return
        }

        self.postOverlayNotification(path: wallpaper.path)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.current_wp = wallpaper.path
            self.screenWallpapers.removeAll()
            self.saveScreenWallpapers()
        }
    }

    private func postOverlayNotification(path: String) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.naomisphere.moonleaf.changeWallpaper"),
            object: nil,
            userInfo: ["filePath": path],
            deliverImmediately: true
        )
    }

    /// Records a wallpaper that the rotation loop already applied: overlay
    /// notice and the "current" marker the browser shows.
    private func mark_current_wallpaper(_ path: String) {
        didMutateWallpaperBeforeInitialLoad = true
        MoonleafConfigStore.shared.writeCurrentWallpaperAsync(path)
        MoonleafConfigStore.shared.writeScreenWallpapersAsync([:])
        postOverlayNotification(path: path)
        DispatchQueue.main.async {
            self.current_wp = path
            self.screenWallpapers.removeAll()
            self.saveScreenWallpapers()
        }
    }

    /// With the per-desktop rotation on, a wallpaper picked by hand belongs to
    /// the desktop it was picked on; the other desktops keep their pictures.
    private func pin_to_current_desktop(_ path: String) {
        guard perSpaceShuffle else { return }
        let spaces = SpaceWallpapers.liveSpaces()
        guard let current = spaces.first(where: { $0.isCurrent }) else { return }

        var wallpaper_of_space = SpaceWallpapers.liveAssignments(for: spaces)
        wallpaper_of_space[current.uuid] = path

        var assignment: [SpaceWallpapers.Space: String] = [:]
        for space in spaces {
            if let wallpaper = wallpaper_of_space[space.uuid] { assignment[space] = wallpaper }
        }
        guard !assignment.isEmpty, SpaceWallpapers.assign(assignment) else { return }
        SpaceWallpapers.reload()
    }

    func set_wp_on_screen(_ wallpaper: endup_wp, screenIndex: Int) {
        let ext = (wallpaper.path as NSString).pathExtension.lowercased()
        let isMoving = ["mov", "mp4", "gif"].contains(ext)
        let isStill = ["jpg", "jpeg", "png"].contains(ext)
        guard isMoving || isStill else { return }

        if isMoving && perSpaceShuffle {
            setPerSpaceShuffle(false)
        }

        if isStill {
            set_wp(wallpaper)
            return
        }

        didMutateWallpaperBeforeInitialLoad = true
        MoonleafConfigStore.shared.writeCurrentWallpaperAsync(wallpaper.path)
        DispatchQueue.main.async {
            self.screenWallpapers[screenIndex] = wallpaper.path
            self.saveScreenWallpapers()
            self.current_wp = wallpaper.path
        }

        GlasswpProcessManager.shared.ensureRunning(perDesktopMode: perSpaceShuffle)

        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.naomisphere.moonleaf.changeWallpaper"),
            object: nil,
            userInfo: ["filePath": wallpaper.path, "screenIndex": screenIndex],
            deliverImmediately: true
        )
    }

    func unset_wp() {
        didMutateWallpaperBeforeInitialLoad = true
        DispatchQueue.main.async {
            self.selected_wp = nil
            self.current_wp = nil
            self.screenWallpapers.removeAll()
        }
        MoonleafConfigStore.shared.writeCurrentWallpaperAsync(nil)
        MoonleafConfigStore.shared.writeScreenWallpapersAsync([:])
        GlasswpProcessManager.shared.stopDaemon()
    }

    func syncAutoStartState(_ enabled: Bool) {
        if Thread.isMainThread {
            if wp_is_agent != enabled {
                wp_is_agent = enabled
            }
        } else {
            DispatchQueue.main.async {
                if self.wp_is_agent != enabled {
                    self.wp_is_agent = enabled
                }
            }
        }
    }

    func wp_doPersist(_ enabled: Bool) {
        wp_is_agent = enabled
        AutoStartManager.setEnabledAsync(enabled) { [weak self] actual in
            self?.wp_is_agent = actual
        }
    }

    func getExportFolder() -> URL {
        MoonleafConfigStore.shared.exportFolderURL()
    }

    private func _exec_wallpaper(_ arguments: [String], completion: @escaping (Bool) -> Void) {
        let cliPath = Bundle.main.bundlePath + "/Contents/Resources/bin/wallpaper"
        // `Process.launch()` raises an uncaught NSException when the helper is
        // missing or not executable, which kills the whole app.
        guard FileManager.default.isExecutableFile(atPath: cliPath) else {
            completion(false)
            return
        }
        DispatchQueue.global(qos: .background).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: cliPath)
            task.arguments = arguments
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                task.waitUntilExit()
                DispatchQueue.main.async { completion(task.terminationStatus == 0) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
    func back() {
        guard !navStack.isEmpty else { return }
        currentPath = navStack.removeLast()
        fetch_wallpapers()
    }

    func navigateTo(folder: endup_wp) {
        guard folder.isFolder else { return }
        if let current = currentPath {
            navStack.append(current)
        }
        currentPath = URL(fileURLWithPath: folder.path)
        fetch_wallpapers()
    }

    func refreshScreenCount() {
        screenCount = NSScreen.screens.count
    }

    private func saveScreenWallpapers() {
        MoonleafConfigStore.shared.writeScreenWallpapersAsync(screenWallpapers)
    }
}

struct endup_wp: Identifiable, Equatable {
    let id: UUID
    let name: String
    let path: String
    let preview: String?
    let createdDate: Date
    let fileSize: Int64
    var isFolder: Bool = false
}