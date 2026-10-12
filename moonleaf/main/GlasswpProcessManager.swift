//
//  GlasswpProcessManager.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import Foundation
import Darwin

final class GlasswpProcessManager {
    static let shared = GlasswpProcessManager()

    private let queue = DispatchQueue(label: "com.naomisphere.moonleaf.glasswpProcess", qos: .userInitiated)
    private var trackedProcess: Process?
    private var adoptedPID: pid_t?

    private var bundledExecutableURL: URL {
        URL(fileURLWithPath: Bundle.main.bundlePath)
            .appendingPathComponent("Contents/Resources/bin/glasswp")
    }

    private init() {}

    func isRunning() -> Bool {
        queue.sync {
            !resolveRunningPIDsLocked().isEmpty
        }
    }

    func ensureRunning(perDesktopMode: Bool, completion: (() -> Void)? = nil) {
        queue.async { [self] in
            let runningPIDs = self.resolveRunningPIDsLocked()
            if let primaryPID = runningPIDs.first {
                self.adoptedPID = primaryPID
                MoonleafConfigStore.shared.writeDaemonPID(primaryPID)

                for extraPID in runningPIDs.dropFirst() where self.isVerifiedGlasswpProcess(extraPID) {
                    _ = kill(extraPID, SIGTERM)
                }

                DispatchQueue.main.async {
                    macpaperService.postPerDesktopMode(perDesktopMode)
                    completion?()
                }
                return
            }

            let execURL = self.bundledExecutableURL
            guard FileManager.default.isExecutableFile(atPath: execURL.path) else {
                DispatchQueue.main.async { completion?() }
                return
            }

            let task = Process()
            task.executableURL = execURL
            task.arguments = ["--daemon"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                let pid = task.processIdentifier
                self.trackedProcess = task
                self.adoptedPID = pid
                MoonleafConfigStore.shared.writeDaemonPID(pid)

                task.terminationHandler = { [weak self] finished in
                    guard let self = self else { return }
                    self.queue.async {
                        let exitedPID = finished.processIdentifier
                        if self.trackedProcess?.processIdentifier == exitedPID {
                            self.trackedProcess = nil
                        }
                        if self.adoptedPID == exitedPID {
                            self.adoptedPID = nil
                        }
                        if MoonleafConfigStore.shared.readDaemonPID() == exitedPID {
                            MoonleafConfigStore.shared.writeDaemonPID(nil)
                        }
                    }
                }
            } catch {
                NSLog("[GlasswpProcessManager] Failed to launch glasswp daemon: %@", error.localizedDescription)
            }

            DispatchQueue.main.async {
                macpaperService.postPerDesktopMode(perDesktopMode)
                completion?()
            }
        }
    }

    func stopDaemon(completion: (() -> Void)? = nil) {

        queue.async {
            let pids = self.resolveRunningPIDsLocked()

            if let proc = self.trackedProcess, proc.isRunning {
                proc.terminate()
            }

            for pid in pids where self.isVerifiedGlasswpProcess(pid) {
                _ = kill(pid, SIGTERM)
            }

            if !pids.isEmpty {
                let deadline = Date().addingTimeInterval(0.4)
                while Date() < deadline {
                    let stillAlive = pids.contains { self.isVerifiedGlasswpProcess($0) }
                    if !stillAlive {
                        break
                    }
                    usleep(25_000)
                }

                for pid in pids where self.isVerifiedGlasswpProcess(pid) {
                    _ = kill(pid, SIGKILL)
                }
            }

            self.trackedProcess = nil
            self.adoptedPID = nil
            MoonleafConfigStore.shared.writeDaemonPID(nil)

            if let completion = completion {
                DispatchQueue.main.async(execute: completion)
            }
        }
    }

    // MARK: - Process Discovery & Verification

    private func resolveRunningPIDsLocked() -> [pid_t] {
        var found: [pid_t] = []

        if let proc = trackedProcess, proc.isRunning {
            let pid = proc.processIdentifier
            if isVerifiedGlasswpProcess(pid) {
                found.append(pid)
            } else {
                trackedProcess = nil
            }
        }

        if let adopted = adoptedPID, !found.contains(adopted) {
            if isVerifiedGlasswpProcess(adopted) {
                found.append(adopted)
            } else {
                adoptedPID = nil
            }
        }

        if let storedPID = MoonleafConfigStore.shared.readDaemonPID(), !found.contains(storedPID) {
            if isVerifiedGlasswpProcess(storedPID) {
                found.append(storedPID)
            } else {
                MoonleafConfigStore.shared.writeDaemonPID(nil)
            }
        }

        for pid in scanProcessTableForGlasswp() where !found.contains(pid) {
            found.append(pid)
        }

        if let first = found.first {
            adoptedPID = first
        }

        return found
    }

    private func scanProcessTableForGlasswp() -> [pid_t] {
        let estimated = proc_listallpids(nil, 0)
        let capacity = max(512, Int(max(0, estimated)) + 128)
        var pids = [pid_t](repeating: 0, count: capacity)
        let bufferBytes = Int32(capacity * MemoryLayout<pid_t>.stride)
        let ret = proc_listallpids(&pids, bufferBytes)
        guard ret > 0 else { return [] }

        var matches: [pid_t] = []
        for pid in pids where pid > 0 {
            if isVerifiedGlasswpProcess(pid) {
                matches.append(pid)
            }
        }
        return matches
    }

    private func isVerifiedGlasswpProcess(_ pid: pid_t) -> Bool {
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier else {
            return false
        }
        guard kill(pid, 0) == 0 else {
            return false
        }
        guard let execPath = executablePath(for: pid) else {
            return false
        }
        let executable = URL(fileURLWithPath: execPath).standardizedFileURL
        return executable == bundledExecutableURL.standardizedFileURL
    }

    private func executablePath(for pid: pid_t) -> String? {
        let maxPathSize = 4 * Int(MAXPATHLEN)
        var buffer = [CChar](repeating: 0, count: maxPathSize)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else {
            return nil
        }
        return String(cString: buffer)
    }
}
