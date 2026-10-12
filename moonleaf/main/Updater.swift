//
//  Updater.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import Foundation
import AppKit
import Sparkle

final class Updater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    private static let defaultRepoPath = "shiquda/moonleaf"

    @MainActor private var updaterController: SPUStandardUpdaterController?
    @MainActor private var pendingAutomaticChecks: Bool?

    private override init() {
        super.init()
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                if NSApp != nil {
                    _ = ensureUpdaterController()
                }
            }
        }
    }

    @MainActor
    @discardableResult
    private func ensureUpdaterController() -> SPUStandardUpdaterController {
        if let controller = updaterController {
            return controller
        }
        let defaultAutoChecks = UserDefaults.standard.object(forKey: "checkForUpdates") as? Bool ?? true
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        updaterController = controller
        let targetAutoChecks = pendingAutomaticChecks ?? defaultAutoChecks
        if controller.updater.automaticallyChecksForUpdates != targetAutoChecks {
            controller.updater.automaticallyChecksForUpdates = targetAutoChecks
        }
        return controller
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            if Thread.isMainThread {
                return MainActor.assumeIsolated {
                    if let controller = updaterController {
                        return controller.updater.automaticallyChecksForUpdates
                    }
                    return pendingAutomaticChecks ?? (UserDefaults.standard.object(forKey: "checkForUpdates") as? Bool ?? true)
                }
            }
            return UserDefaults.standard.object(forKey: "checkForUpdates") as? Bool ?? true
        }
        set {
            let apply = { @MainActor in
                self.pendingAutomaticChecks = newValue
                guard NSApp != nil else { return }
                let controller = self.ensureUpdaterController()
                if controller.updater.automaticallyChecksForUpdates != newValue {
                    controller.updater.automaticallyChecksForUpdates = newValue
                }
            }
            if Thread.isMainThread {
                MainActor.assumeIsolated(apply)
            } else {
                DispatchQueue.main.async(execute: apply)
            }
        }
    }

    func checkForUpdates() {
        let runCheck = { @MainActor in
            let controller = self.ensureUpdaterController()
            NSApp.activate(ignoringOtherApps: true)
            controller.checkForUpdates(nil)
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(runCheck)
        } else {
            DispatchQueue.main.async(execute: runCheck)
        }
    }

    func resetUpdateCycleAfterShortDelay() {
        let reset = { @MainActor in
            guard NSApp != nil else { return }
            self.ensureUpdaterController().updater.resetUpdateCycleAfterShortDelay()
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(reset)
        } else {
            DispatchQueue.main.async(execute: reset)
        }
    }
    func fetchChangelog(completion: @escaping (String?) -> Void) {
        guard let url = changelogURL else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let body = json["body"] as? String else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async {
                completion(body)
            }
        }.resume()
    }

    private var customServerRepoPath: String? {
        let rawServer = MoonleafConfigStore.shared.readUpdateServer()
        guard !rawServer.isEmpty else {
            return nil
        }
        let trimmed = rawServer
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = "github.com/"
        guard trimmed.lowercased().hasPrefix(prefix) else {
            return nil
        }
        let repoPath = String(trimmed.dropFirst(prefix.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return repoPath.isEmpty ? nil : repoPath
    }

    private var apiBaseUrl: String {
        let repoPath = customServerRepoPath ?? Self.defaultRepoPath
        return "https://api.github.com/repos/\(repoPath)"
    }

    private var changelogURL: URL? {
        URL(string: "\(apiBaseUrl)/releases/latest")
    }

    // MARK: - SPUUpdaterDelegate

    @MainActor
    func feedURLString(for updater: SPUUpdater) -> String? {
        guard let repoPath = customServerRepoPath else {
            return nil
        }
        return "https://github.com/\(repoPath)/releases/latest/download/appcast.xml"
    }

    @MainActor
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        NSLog("[Sparkle] Found valid update: %@ (%@)", item.displayVersionString, item.versionString)
    }

    @MainActor
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        let nsError = error as NSError
        if let reason = nsError.userInfo[SPUNoUpdateFoundReasonKey] {
            NSLog("[Sparkle] No update found (reason: %@)", String(describing: reason))
        } else {
            NSLog("[Sparkle] No update found")
        }
    }

    @MainActor
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        guard !Self.isBenignSparkleError(error) else { return }
        NSLog("[Sparkle] Update check aborted with error: %@", error.localizedDescription)
    }

    @MainActor
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error = error, !Self.isBenignSparkleError(error) {
            NSLog("[Sparkle] Update cycle (%d) finished with error: %@", updateCheck.rawValue, error.localizedDescription)
        }
    }

    private static func isBenignSparkleError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == SUSparkleErrorDomain else { return false }
        return nsError.code == Int(SUError.noUpdateError.rawValue)
            || nsError.code == Int(SUError.installationCanceledError.rawValue)
            || nsError.code == Int(SUError.installationAuthorizeLaterError.rawValue)
    }

    // MARK: - SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
