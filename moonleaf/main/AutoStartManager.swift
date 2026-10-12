//
//  AutoStartManager.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import Foundation
import ServiceManagement

enum AutoStartManager {
    enum RegistrationState: Equatable {
        case enabled
        case requiresApproval
        case disabled

        var isActiveOrPendingApproval: Bool {
            switch self {
            case .enabled, .requiresApproval:
                return true
            case .disabled:
                return false
            }
        }
    }

    static let plistName = "com.naomisphere.macpaper.app.plist"
    private static let appBundleIdentifier = "com.naomisphere.macpaper"
    private static let legacyWallpaperPlistNames = [
        "com.naomisphere.macpaper.wallpaper.plist",
        "com.naomisphere.moonleaf.wallpaper.plist",
    ]
    private static let migrationKey = "didMigrateAutoStartToSMAppService"
    private static let autoStartDefaultsKey = "autoStartEnabled"

    private static let queue = DispatchQueue(label: "com.naomisphere.moonleaf.autostart")
    private static var hasMigratedInProcess = false

    private static var ownsLoginItem: Bool {
        guard Bundle.main.bundleIdentifier == appBundleIdentifier else { return false }
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchAgents/\(plistName)")
        guard let data = try? Data(contentsOf: url),
              let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
              let associated = plist["AssociatedBundleIdentifiers"] as? [String] else { return false }
        return associated.contains(appBundleIdentifier)
    }

    private static var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    static var legacyPlistURL: URL {
        launchAgentsDirectory.appendingPathComponent(plistName)
    }

    private static var allLegacyPlistURLs: [URL] {
        var urls = [legacyPlistURL]
        for name in legacyWallpaperPlistNames {
            urls.append(launchAgentsDirectory.appendingPathComponent(name))
        }
        return urls
    }

    private static func runLaunchctl(_ arguments: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus
        } catch {
            NSLog("[AutoStartManager] launchctl %@ failed: %@", arguments.joined(separator: " "), error.localizedDescription)
            return -1
        }
    }

    private static func legacyJobCouldBeThisProcess(label: String) -> Bool {
        let task = Process()
        let output = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["print", "gui/\(getuid())/\(label)"]
        task.standardOutput = output
        task.standardError = output
        do {
            try task.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            if task.terminationStatus != 0 {
                // A missing job is safe to migrate; any other query failure is not.
                return !text.contains("Could not find service")
            }
            return text.range(of: "(?m)^\\s*pid = \(getpid())\\s*$", options: .regularExpression) != nil
        } catch {
            return true
        }
    }

    @discardableResult
    private static func bootoutAndRemovePlistLocked(at url: URL, preserveRunningAppJob: Bool = true) -> (existed: Bool, removedCleanly: Bool) {
        let fm = FileManager.default
        let path = url.path
        guard fm.fileExists(atPath: path) else {
            return (false, true)
        }

        // Defer migration when bootout would kill us. Keep the old plist so next login
        // remains enabled until a manual launch can safely register its replacement.
        let data = try? Data(contentsOf: url)
        let plist = data.flatMap { try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) } as? [String: Any]
        let program = (plist?["Program"] as? String)
            ?? (plist?["ProgramArguments"] as? [String])?.first
            ?? (plist?["BundleProgram"] as? String).map { Bundle.main.bundleURL.appendingPathComponent($0).path }
        let launchesThisExecutable = program.map {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath() == Bundle.main.executableURL?.resolvingSymlinksInPath()
        } ?? false
        let couldBeThisProcess = launchesThisExecutable && ((plist?["Label"] as? String).map {
            legacyJobCouldBeThisProcess(label: $0)
        } ?? true)
        if couldBeThisProcess && preserveRunningAppJob {
            return (true, false)
        }
        if !couldBeThisProcess {
            let bootoutStatus = runLaunchctl(["bootout", "gui/\(getuid())", path])
            if bootoutStatus != 0 {
                _ = runLaunchctl(["unload", path])
            }
        }

        do {
            try fm.removeItem(at: url)
        } catch {
            NSLog("[AutoStartManager] Failed to remove legacy LaunchAgent plist at %@: %@", path, error.localizedDescription)
        }

        let removedCleanly = !fm.fileExists(atPath: path)
        return (true, removedCleanly)
    }

    @discardableResult
    private static func removeAllLegacyPlistsLocked(preserveRunningAppJob: Bool = true) -> (existedAny: Bool, allRemovedCleanly: Bool) {
        var existedAny = false
        var allClean = true
        for url in allLegacyPlistURLs {
            let result = bootoutAndRemovePlistLocked(at: url, preserveRunningAppJob: preserveRunningAppJob)
            if result.existed {
                existedAny = true
            }
            if !result.removedCleanly {
                allClean = false
            }
        }
        return (existedAny, allClean)
    }

    static func migrateLegacyIfNeededAsync(completion: ((Bool) -> Void)? = nil) {
        queue.async {
            migrateLegacyIfNeededLocked()
            let enabled = registrationStateLocked().isActiveOrPendingApproval
            DispatchQueue.main.async {
                macpaperService.shared.syncAutoStartState(enabled)
                completion?(enabled)
            }
        }
    }

    private static func migrateLegacyIfNeededLocked() {
        guard ownsLoginItem else { return }
        if hasMigratedInProcess {
            return
        }

        guard #available(macOS 13.0, *) else {
            // On macOS 12, still migrate any legacy wallpaper LaunchAgent into the app LaunchAgent.
            var hadLegacyWallpaperAgent = false
            var allClean = true
            for name in legacyWallpaperPlistNames {
                let url = launchAgentsDirectory.appendingPathComponent(name)
                let result = bootoutAndRemovePlistLocked(at: url)
                if result.existed {
                    hadLegacyWallpaperAgent = true
                }
                if !result.removedCleanly {
                    allClean = false
                }
            }
            if hadLegacyWallpaperAgent && !FileManager.default.fileExists(atPath: legacyPlistURL.path) {
                if !setLegacyAppPlistEnabledLocked(true) {
                    allClean = false
                }
            }
            if allClean {
                hasMigratedInProcess = true
            }
            return
        }

        let removal = removeAllLegacyPlistsLocked()
        guard removal.allRemovedCleanly else {
            return
        }

        let alreadyMigrated = UserDefaults.standard.bool(forKey: migrationKey)
        guard removal.existedAny || !alreadyMigrated else {
            hasMigratedInProcess = true
            return
        }

        let shouldEnable = removal.existedAny || UserDefaults.standard.bool(forKey: autoStartDefaultsKey)
        let service = SMAppService.agent(plistName: plistName)

        if !shouldEnable {
            let active = (service.status == .enabled || service.status == .requiresApproval)
            UserDefaults.standard.set(active, forKey: autoStartDefaultsKey)
            UserDefaults.standard.set(true, forKey: migrationKey)
            hasMigratedInProcess = true
            return
        }

        if removal.existedAny || (service.status != .enabled && service.status != .requiresApproval) {
            do {
                try service.register()
            } catch {
                NSLog("[AutoStartManager] Failed to register SMAppService during migration: %@", error.localizedDescription)
            }
        }

        let status = service.status
        let registered = (status == .enabled || status == .requiresApproval)
        UserDefaults.standard.set(registered, forKey: autoStartDefaultsKey)

        if registered {
            UserDefaults.standard.set(true, forKey: migrationKey)
            hasMigratedInProcess = true
        }
    }


    private static func registrationStateLocked() -> RegistrationState {
        guard ownsLoginItem else { return .disabled }
        migrateLegacyIfNeededLocked()
        if #available(macOS 13.0, *) {
            switch SMAppService.agent(plistName: plistName).status {
            case .enabled:
                return .enabled
            case .requiresApproval:
                return .requiresApproval
            case .notRegistered, .notFound:
                return FileManager.default.fileExists(atPath: legacyPlistURL.path) ? .enabled : .disabled
            @unknown default:
                return .disabled
            }
        }
        return FileManager.default.fileExists(atPath: legacyPlistURL.path) ? .enabled : .disabled
    }

    static func setEnabledAsync(_ enabled: Bool, completion: ((Bool) -> Void)? = nil) {
        queue.async {
            let actual = setEnabledLocked(enabled)
            DispatchQueue.main.async {
                macpaperService.shared.syncAutoStartState(actual)
                completion?(actual)
            }
        }
    }

    private static func setEnabledLocked(_ enabled: Bool) -> Bool {
        guard ownsLoginItem else { return false }
        if #available(macOS 13.0, *) {
            let service = SMAppService.agent(plistName: plistName)
            if enabled, service.status != .enabled, service.status != .requiresApproval,
               legacyJobCouldBeThisProcess(label: String(plistName.dropLast(".plist".count))) {
                // A disabled legacy job can remain loaded for this session. Restore its
                // plist instead of registering a conflicting replacement under the same label.
                let actual = setLegacyAppPlistEnabledLocked(true, loadJob: false)
                UserDefaults.standard.set(actual, forKey: autoStartDefaultsKey)
                return actual
            }
            let removal = removeAllLegacyPlistsLocked(preserveRunningAppJob: enabled)
            guard removal.allRemovedCleanly else {
                return registrationStateLocked().isActiveOrPendingApproval
            }

            if enabled {
                if service.status != .enabled && service.status != .requiresApproval {
                    do {
                        try service.register()
                    } catch {
                        NSLog("[AutoStartManager] Failed to register login item: %@", error.localizedDescription)
                    }
                }
                let active = (service.status == .enabled || service.status == .requiresApproval)
                UserDefaults.standard.set(active, forKey: autoStartDefaultsKey)
                if active && removal.allRemovedCleanly {
                    UserDefaults.standard.set(true, forKey: migrationKey)
                    hasMigratedInProcess = true
                }
                return active
            } else {
                if service.status == .enabled || service.status == .requiresApproval {
                    // Unregister can terminate this app when it was started by the agent.
                    UserDefaults.standard.set(false, forKey: autoStartDefaultsKey)
                    UserDefaults.standard.synchronize()
                    do {
                        try service.unregister()
                    } catch {
                        NSLog("[AutoStartManager] Failed to unregister login item: %@", error.localizedDescription)
                    }
                }
                let active = (service.status == .enabled || service.status == .requiresApproval)
                UserDefaults.standard.set(active, forKey: autoStartDefaultsKey)
                if !active && removal.allRemovedCleanly {
                    UserDefaults.standard.set(true, forKey: migrationKey)
                    hasMigratedInProcess = true
                }
                return active
            }
        }

        for name in legacyWallpaperPlistNames {
            _ = bootoutAndRemovePlistLocked(at: launchAgentsDirectory.appendingPathComponent(name))
        }
        let actual = setLegacyAppPlistEnabledLocked(enabled)
        UserDefaults.standard.set(actual, forKey: autoStartDefaultsKey)
        return actual
    }

    private static func setLegacyAppPlistEnabledLocked(_ enabled: Bool, loadJob: Bool = true) -> Bool {
        let launchAgent = legacyPlistURL
        let executablePath = Bundle.main.executableURL?.path
            ?? "\(Bundle.main.bundlePath)/Contents/MacOS/moonleaf"

        if enabled {
            let plist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>\(String(plistName.dropLast(".plist".count)))</string>
    <key>AssociatedBundleIdentifiers</key>
    <array>
        <string>\(appBundleIdentifier)</string>
    </array>
    <key>ProgramArguments</key>
    <array>
        <string>\(executablePath)</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
"""
            do {
                try FileManager.default.createDirectory(
                    at: launchAgent.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try plist.write(to: launchAgent, atomically: true, encoding: .utf8)
                if loadJob {
                    _ = runLaunchctl(["load", launchAgent.path])
                }
                return true
            } catch {
                NSLog("[AutoStartManager] Failed to write legacy LaunchAgent plist: %@", error.localizedDescription)
                return false
            }
        } else {
            _ = bootoutAndRemovePlistLocked(at: launchAgent, preserveRunningAppJob: false)
            return false
        }
    }
}
