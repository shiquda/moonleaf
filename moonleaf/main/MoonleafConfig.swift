//
//  MoonleafConfig.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import Foundation
import Darwin

enum AnyCodableValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([AnyCodableValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: AnyCodableValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        case .null: try container.encodeNil()
        }
    }
}

struct MoonleafSettings: Codable, Equatable {
    var ap_is_enabled: Bool = false
    var showVideos: Bool = true
    var showImages: Bool = true
    var import_method: String = "link"

    var visualizer_mode: String = "disabled"
    var visualizer_colorMode: String = "rainbow"
    var visualizer_customColor: String = "#FF00FF"
    var visualizer_transparency: Double = 0.6
    var visualizer_barCount: Int = 64
    var visualizer_maxHeight: Double = 0.5
    var visualizer_minHeight: Double = 4.0

    var scalingMode: String = "fill"
    var videoFilter: String = "none"

    var additionalFields: [String: AnyCodableValue] = [:]

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }

        init(_ key: String) {
            self.stringValue = key
            self.intValue = nil
        }
    }

    private static let knownKeys: Set<String> = [
        "ap_is_enabled",
        "showVideos",
        "showImages",
        "import_method",
        "visualizer_mode",
        "visualizer_colorMode",
        "visualizer_customColor",
        "visualizer_transparency",
        "visualizer_barCount",
        "visualizer_maxHeight",
        "visualizer_minHeight",
        "scalingMode",
        "videoFilter",
    ]

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)

        ap_is_enabled = Self.decodeBool(from: container, key: "ap_is_enabled", default: false)
        showVideos = Self.decodeBool(from: container, key: "showVideos", default: true)
        showImages = Self.decodeBool(from: container, key: "showImages", default: true)
        import_method = Self.decodeString(from: container, key: "import_method", default: "link")

        visualizer_mode = Self.decodeString(from: container, key: "visualizer_mode", default: "disabled")
        visualizer_colorMode = Self.decodeString(from: container, key: "visualizer_colorMode", default: "rainbow")
        visualizer_customColor = Self.decodeString(from: container, key: "visualizer_customColor", default: "#FF00FF")
        visualizer_transparency = Self.decodeDouble(from: container, key: "visualizer_transparency", default: 0.6)
        visualizer_barCount = Self.decodeInt(from: container, key: "visualizer_barCount", default: 64)
        visualizer_maxHeight = Self.decodeDouble(from: container, key: "visualizer_maxHeight", default: 0.5)
        visualizer_minHeight = Self.decodeDouble(from: container, key: "visualizer_minHeight", default: 4.0)

        scalingMode = Self.decodeString(from: container, key: "scalingMode", default: "fill")
        videoFilter = Self.decodeString(from: container, key: "videoFilter", default: "none")

        var extra: [String: AnyCodableValue] = [:]
        for key in container.allKeys where !Self.knownKeys.contains(key.stringValue) {
            if let value = try? container.decode(AnyCodableValue.self, forKey: key) {
                extra[key.stringValue] = value
            }
        }
        additionalFields = extra
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)

        for (key, value) in additionalFields where !Self.knownKeys.contains(key) {
            try container.encode(value, forKey: DynamicKey(key))
        }

        try container.encode(ap_is_enabled, forKey: DynamicKey("ap_is_enabled"))
        try container.encode(showVideos, forKey: DynamicKey("showVideos"))
        try container.encode(showImages, forKey: DynamicKey("showImages"))
        try container.encode(import_method, forKey: DynamicKey("import_method"))

        try container.encode(visualizer_mode, forKey: DynamicKey("visualizer_mode"))
        try container.encode(visualizer_colorMode, forKey: DynamicKey("visualizer_colorMode"))
        try container.encode(visualizer_customColor, forKey: DynamicKey("visualizer_customColor"))
        try container.encode(visualizer_transparency, forKey: DynamicKey("visualizer_transparency"))
        try container.encode(visualizer_barCount, forKey: DynamicKey("visualizer_barCount"))
        try container.encode(visualizer_maxHeight, forKey: DynamicKey("visualizer_maxHeight"))
        try container.encode(visualizer_minHeight, forKey: DynamicKey("visualizer_minHeight"))

        try container.encode(scalingMode, forKey: DynamicKey("scalingMode"))
        try container.encode(videoFilter, forKey: DynamicKey("videoFilter"))
    }

    private static func decodeBool(
        from container: KeyedDecodingContainer<DynamicKey>,
        key: String,
        default defaultValue: Bool
    ) -> Bool {
        let codingKey = DynamicKey(key)
        if let b = try? container.decodeIfPresent(Bool.self, forKey: codingKey) {
            return b
        }
        if let s = try? container.decodeIfPresent(String.self, forKey: codingKey) {
            switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: break
            }
        }
        if let i = try? container.decodeIfPresent(Int.self, forKey: codingKey) {
            return i != 0
        }
        return defaultValue
    }

    private static func decodeInt(
        from container: KeyedDecodingContainer<DynamicKey>,
        key: String,
        default defaultValue: Int
    ) -> Int {
        let codingKey = DynamicKey(key)
        if let i = try? container.decodeIfPresent(Int.self, forKey: codingKey) {
            return i
        }
        if let d = try? container.decodeIfPresent(Double.self, forKey: codingKey) {
            return Int(d)
        }
        if let s = try? container.decodeIfPresent(String.self, forKey: codingKey),
           let parsed = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed
        }
        return defaultValue
    }

    private static func decodeDouble(
        from container: KeyedDecodingContainer<DynamicKey>,
        key: String,
        default defaultValue: Double
    ) -> Double {
        let codingKey = DynamicKey(key)
        if let d = try? container.decodeIfPresent(Double.self, forKey: codingKey) {
            return d
        }
        if let i = try? container.decodeIfPresent(Int.self, forKey: codingKey) {
            return Double(i)
        }
        if let s = try? container.decodeIfPresent(String.self, forKey: codingKey),
           let parsed = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed
        }
        return defaultValue
    }

    private static func decodeString(
        from container: KeyedDecodingContainer<DynamicKey>,
        key: String,
        default defaultValue: String
    ) -> String {
        let codingKey = DynamicKey(key)
        if let s = try? container.decodeIfPresent(String.self, forKey: codingKey) {
            return s
        }
        return defaultValue
    }
}

final class MoonleafConfigStore {
    static let shared = MoonleafConfigStore()

    private static let home = FileManager.default.homeDirectoryForCurrentUser
    static let configRoot = home.appendingPathComponent(".config/moonleaf")
    static let legacyConfigRoot = home.appendingPathComponent(".local/share/macpaper")
    static let libraryRoot = home.appendingPathComponent(".local/share/paper/wallpaper")

    static let settingsFile = configRoot.appendingPathComponent("settings.json")
    static let volumeFile = configRoot.appendingPathComponent("volume")
    static let screenWallpapersFile = configRoot.appendingPathComponent("screen_wallpapers.json")
    static let currentWallpaperFile = configRoot.appendingPathComponent("current_wallpaper")
    static let exportFolderFile = configRoot.appendingPathComponent("export_folder")
    static let wallhavenAPIKeyFile = configRoot.appendingPathComponent("WH_API_KEY")
    static let pexelsAPIKeyFile = configRoot.appendingPathComponent("pexels_api_key.txt")
    static let updateServerFile = configRoot.appendingPathComponent("update_server")
    static let glasswpPIDFile = configRoot.appendingPathComponent("glasswp.pid")

    private static let migrationDefaultsKey = "didMigrateConfigToMoonleafCanonical"

    private static let knownLegacyConfigFiles: [String] = [
        "settings.json",
        "volume",
        "screen_wallpapers.json",
        "current_wallpaper",
        "export_folder",
        "WH_API_KEY",
        "pexels_api_key.txt",
        "update_server",
    ]

    struct StartupSnapshot {
        let settings: MoonleafSettings
        let volume: Double
        let currentWallpaper: String?
        let screenWallpapers: [Int: String]
    }

    private let queue = DispatchQueue(label: "com.naomisphere.moonleaf.configStore", qos: .userInitiated)
    private var hasMigratedInProcess = false
    private var pendingVolumeValue: Double?
    private var volumeWriteWorkItem: DispatchWorkItem?

    private init() {}

    func loadStartupSnapshotAsync(completion: @escaping (StartupSnapshot) -> Void) {
        queue.async {
            self.ensureMigratedLocked()
            let snapshot = StartupSnapshot(
                settings: self.loadSettingsLocked(),
                volume: self.readVolumeLocked(),
                currentWallpaper: self.readCurrentWallpaperLocked(),
                screenWallpapers: self.readScreenWallpapersLocked()
            )
            DispatchQueue.main.async {
                completion(snapshot)
            }
        }
    }
    func migrateIfNeeded() {
        queue.sync {
            ensureMigratedLocked()
        }
    }

    func migrateIfNeededAsync(completion: (() -> Void)? = nil) {
        queue.async {
            self.ensureMigratedLocked()
            if let completion = completion {
                DispatchQueue.main.async(execute: completion)
            }
        }
    }

    private func ensureMigratedLocked() {
        if hasMigratedInProcess {
            return
        }

        let fm = FileManager.default
        var migrationSucceeded = true

        do {
            try fm.createDirectory(at: Self.configRoot, withIntermediateDirectories: true)
        } catch {
            return
        }

        // App and engine have different UserDefaults domains but migrate the same files.
        let lockPath = Self.configRoot.appendingPathComponent(".migration.lock").path
        let lockFD = Darwin.open(lockPath, O_CREAT | O_RDWR, mode_t(0o600))
        guard lockFD >= 0 else { return }
        defer { Darwin.close(lockFD) }
        guard Darwin.lockf(lockFD, F_LOCK, 0) == 0 else { return }
        defer { _ = Darwin.lockf(lockFD, F_ULOCK, 0) }
        let marker = Self.configRoot.appendingPathComponent(".canonical-migration-v1")

        // Materialize any known config symlinks inside ~/.config/moonleaf via temp sibling + atomic rename.
        for fileName in Self.knownLegacyConfigFiles {
            let itemURL = Self.configRoot.appendingPathComponent(fileName)
            guard isSymbolicLink(itemURL) else { continue }
            let resolved = itemURL.resolvingSymlinksInPath()
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: resolved.path, isDirectory: &isDir), !isDir.boolValue else {
                continue
            }
            do {
                let data = try Data(contentsOf: resolved)
                try atomicWriteReplacingSymlinkOrFile(data, to: itemURL)
            } catch {
                migrationSucceeded = false
            }
        }

        if fm.fileExists(atPath: marker.path) || UserDefaults.standard.bool(forKey: Self.migrationDefaultsKey) {
            if migrationSucceeded {
                do {
                    try Data().write(to: marker, options: .atomic)
                    hasMigratedInProcess = true
                } catch {
                    NSLog("[MoonleafConfigStore] Failed to record config migration: %@", error.localizedDescription)
                }
            }
            return
        }

        // One-time migration of known config files from legacy ~/.local/share/macpaper into ~/.config/moonleaf.
        if fm.fileExists(atPath: Self.legacyConfigRoot.path) {
            for fileName in Self.knownLegacyConfigFiles {
                let legacyItem = Self.legacyConfigRoot.appendingPathComponent(fileName)
                guard !isSymbolicLink(legacyItem) else { continue }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: legacyItem.path, isDirectory: &isDir), !isDir.boolValue else {
                    continue
                }

                let destURL = Self.configRoot.appendingPathComponent(fileName)

                if fileName == "settings.json",
                   fm.fileExists(atPath: destURL.path),
                   let legacyData = try? Data(contentsOf: legacyItem),
                   let currentData = try? Data(contentsOf: destURL),
                   let legacyObj = (try? JSONSerialization.jsonObject(with: legacyData)) as? [String: Any],
                   var currentObj = (try? JSONSerialization.jsonObject(with: currentData)) as? [String: Any] {
                    var changed = false
                    for (k, v) in legacyObj where currentObj[k] == nil {
                        currentObj[k] = v
                        changed = true
                    }
                    if changed {
                        do {
                            let mergedData = try JSONSerialization.data(
                                withJSONObject: currentObj,
                                options: [.prettyPrinted, .sortedKeys]
                            )
                            try atomicWriteReplacingSymlinkOrFile(mergedData, to: destURL)
                        } catch {
                            migrationSucceeded = false
                        }
                    }
                } else if !fm.fileExists(atPath: destURL.path) {
                    do {
                        let data = try Data(contentsOf: legacyItem)
                        try atomicWriteReplacingSymlinkOrFile(data, to: destURL)
                    } catch {
                        migrationSucceeded = false
                    }
                }
            }
        }

        if migrationSucceeded {
            do {
                try Data().write(to: marker, options: .atomic)
                UserDefaults.standard.set(true, forKey: Self.migrationDefaultsKey)
                hasMigratedInProcess = true
            } catch {
                NSLog("[MoonleafConfigStore] Failed to record config migration: %@", error.localizedDescription)
            }
        }
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let type = attrs[.type] as? FileAttributeType else {
            return false
        }
        return type == .typeSymbolicLink
    }

    private func atomicWriteReplacingSymlinkOrFile(_ data: Data, to destinationURL: URL) throws {
        let dirURL = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let tempURL = dirURL.appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: tempURL, options: .atomic)
        if Darwin.rename(tempURL.path, destinationURL.path) != 0 {
            let err = errno
            try? FileManager.default.removeItem(at: tempURL)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(err))
        }
    }
    // MARK: - Typed Settings (settings.json)

    func loadSettings() -> MoonleafSettings {
        queue.sync {
            ensureMigratedLocked()
            return loadSettingsLocked()
        }
    }

    func saveSettings(_ settings: MoonleafSettings) throws {
        try queue.sync {
            ensureMigratedLocked()
            try saveSettingsLocked(settings)
        }
    }

    @discardableResult
    func updateSettings(_ mutate: (inout MoonleafSettings) -> Void) -> MoonleafSettings {
        queue.sync {
            ensureMigratedLocked()
            var settings = loadSettingsLocked()
            mutate(&settings)
            try? saveSettingsLocked(settings)
            return settings
        }
    }

    func updateSettingsAsync(
        _ mutate: @escaping (inout MoonleafSettings) -> Void,
        completion: ((MoonleafSettings) -> Void)? = nil
    ) {
        queue.async {
            self.ensureMigratedLocked()
            var settings = self.loadSettingsLocked()
            mutate(&settings)
            try? self.saveSettingsLocked(settings)
            if let completion = completion {
                DispatchQueue.main.async {
                    completion(settings)
                }
            }
        }
    }
    private func loadSettingsLocked() -> MoonleafSettings {
        guard let data = try? Data(contentsOf: Self.settingsFile),
              let decoded = try? JSONDecoder().decode(MoonleafSettings.self, from: data) else {
            return MoonleafSettings()
        }
        return decoded
    }

    private func saveSettingsLocked(_ settings: MoonleafSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try atomicWriteReplacingSymlinkOrFile(data, to: Self.settingsFile)
    }

    // MARK: - Volume

    func readVolume() -> Double {
        queue.sync {
            ensureMigratedLocked()
            return readVolumeLocked()
        }
    }

    func writeVolume(_ volume: Double) {
        queue.sync {
            volumeWriteWorkItem?.cancel()
            volumeWriteWorkItem = nil
            pendingVolumeValue = nil
            ensureMigratedLocked()
            writeVolumeLocked(volume)
        }
    }

    func writeVolumeThrottled(_ volume: Double, delay: TimeInterval = 0.15) {
        let clamped = max(0.0, min(1.0, volume))
        queue.async { [self] in
            self.pendingVolumeValue = clamped
            guard self.volumeWriteWorkItem == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.volumeWriteWorkItem = nil
                guard let latest = self.pendingVolumeValue else { return }
                self.pendingVolumeValue = nil
                self.ensureMigratedLocked()
                self.writeVolumeLocked(latest)
            }
            self.volumeWriteWorkItem = work
            self.queue.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func readVolumeLocked() -> Double {
        if let pending = pendingVolumeValue {
            return max(0.0, min(1.0, pending))
        }
        guard let data = try? Data(contentsOf: Self.volumeFile),
              let str = String(data: data, encoding: .utf8),
              let intVal = Int(str.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 0.5
        }
        return Double(max(0, min(100, intVal))) / 100.0
    }

    private func writeVolumeLocked(_ volume: Double) {
        let percentage = max(0, min(100, Int((volume * 100.0).rounded())))
        if let data = "\(percentage)".data(using: .utf8) {
            try? atomicWriteReplacingSymlinkOrFile(data, to: Self.volumeFile)
        }
    }

    // MARK: - Screen Wallpapers & Current Wallpaper

    func readScreenWallpapers() -> [Int: String] {
        queue.sync {
            ensureMigratedLocked()
            return readScreenWallpapersLocked()
        }
    }

    func writeScreenWallpapers(_ wallpapers: [Int: String]) {
        queue.sync {
            ensureMigratedLocked()
            writeScreenWallpapersLocked(wallpapers)
        }
    }

    func writeScreenWallpapersAsync(_ wallpapers: [Int: String]) {
        queue.async {
            self.ensureMigratedLocked()
            self.writeScreenWallpapersLocked(wallpapers)
        }
    }

    private func readScreenWallpapersLocked() -> [Int: String] {
        guard let data = try? Data(contentsOf: Self.screenWallpapersFile),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        var loaded: [Int: String] = [:]
        for (key, path) in decoded {
            if let idx = Int(key) {
                loaded[idx] = path
            }
        }
        return loaded
    }

    private func writeScreenWallpapersLocked(_ wallpapers: [Int: String]) {
        var encoded: [String: String] = [:]
        for (idx, path) in wallpapers {
            encoded[String(idx)] = path
        }
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        try? atomicWriteReplacingSymlinkOrFile(data, to: Self.screenWallpapersFile)
    }

    func readCurrentWallpaper() -> String? {
        queue.sync {
            ensureMigratedLocked()
            return readCurrentWallpaperLocked()
        }
    }

    func writeCurrentWallpaper(_ path: String?) {
        queue.sync {
            ensureMigratedLocked()
            writeCurrentWallpaperLocked(path)
        }
    }

    func writeCurrentWallpaperAsync(_ path: String?) {
        queue.async {
            self.ensureMigratedLocked()
            self.writeCurrentWallpaperLocked(path)
        }
    }

    private func readCurrentWallpaperLocked() -> String? {
        guard let raw = try? String(contentsOf: Self.currentWallpaperFile, encoding: .utf8) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, FileManager.default.fileExists(atPath: trimmed) else {
            return nil
        }
        return trimmed
    }

    private func writeCurrentWallpaperLocked(_ path: String?) {
        let fm = FileManager.default
        if let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty,
           let data = path.data(using: .utf8) {
            try? atomicWriteReplacingSymlinkOrFile(data, to: Self.currentWallpaperFile)
        } else {
            if fm.fileExists(atPath: Self.currentWallpaperFile.path) || isSymbolicLink(Self.currentWallpaperFile) {
                try? fm.removeItem(at: Self.currentWallpaperFile)
            }
            let legacyCurrent = Self.legacyConfigRoot.appendingPathComponent("current_wallpaper")
            if fm.fileExists(atPath: legacyCurrent.path) || isSymbolicLink(legacyCurrent) {
                try? fm.removeItem(at: legacyCurrent)
            }
        }
    }

    // MARK: - Export Folder, API Keys & Update Server

    func readExportFolderPath() -> String {
        readTrimmedString(from: Self.exportFolderFile)
    }

    func writeExportFolderPath(_ path: String) throws {
        try writeTrimmedString(path, to: Self.exportFolderFile)
    }

    func exportFolderURL() -> URL {
        let customPath = readExportFolderPath()
        if !customPath.isEmpty && FileManager.default.fileExists(atPath: customPath) {
            return URL(fileURLWithPath: customPath)
        }
        return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? Self.home.appendingPathComponent("Pictures")
    }

    func readWallhavenAPIKey() -> String {
        readTrimmedString(from: Self.wallhavenAPIKeyFile)
    }

    func writeWallhavenAPIKey(_ key: String) throws {
        try writeTrimmedString(key, to: Self.wallhavenAPIKeyFile)
    }

    func readPexelsAPIKey() -> String {
        readTrimmedString(from: Self.pexelsAPIKeyFile)
    }

    func writePexelsAPIKey(_ key: String) throws {
        try writeTrimmedString(key, to: Self.pexelsAPIKeyFile)
    }

    func readUpdateServer() -> String {
        readTrimmedString(from: Self.updateServerFile)
    }

    func writeUpdateServer(_ server: String) throws {
        try writeTrimmedString(server, to: Self.updateServerFile)
    }

    // MARK: - Daemon PID Tracking

    func readDaemonPID() -> pid_t? {
        queue.sync {
            ensureMigratedLocked()
            guard let raw = try? String(contentsOf: Self.glasswpPIDFile, encoding: .utf8),
                  let pidVal = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
                  pidVal > 0 else {
                return nil
            }
            return pidVal
        }
    }

    func writeDaemonPID(_ pid: pid_t?) {
        queue.sync {
            ensureMigratedLocked()
            let fm = FileManager.default
            if let pid = pid, pid > 0, let data = "\(pid)".data(using: .utf8) {
                try? atomicWriteReplacingSymlinkOrFile(data, to: Self.glasswpPIDFile)
            } else if fm.fileExists(atPath: Self.glasswpPIDFile.path) {
                try? fm.removeItem(at: Self.glasswpPIDFile)
            }
        }
    }

    // MARK: - String File Helpers

    private func readTrimmedString(from url: URL) -> String {
        queue.sync {
            ensureMigratedLocked()
            guard FileManager.default.fileExists(atPath: url.path),
                  let content = try? String(contentsOf: url, encoding: .utf8) else {
                return ""
            }
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func writeTrimmedString(_ value: String, to url: URL) throws {
        try queue.sync {
            ensureMigratedLocked()
            try writeTrimmedStringLocked(value, to: url)
        }
    }

    private func writeTrimmedStringLocked(_ value: String, to url: URL) throws {
        let fm = FileManager.default
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if fm.fileExists(atPath: url.path) || isSymbolicLink(url) {
                try fm.removeItem(at: url)
            }
        } else if let data = trimmed.data(using: .utf8) {
            try atomicWriteReplacingSymlinkOrFile(data, to: url)
        }
    }
}
