//
//  SpaceOverlay.swift
//  glasswp
//
//  One window per display that a video target actually occupies.
//  Windows do not join every Space. A failed bind is reported, never
//  papered over with a global overlay.
//

import AppKit
import Foundation

final class SpaceOverlayController {
    var configure: (ScreenPlayer) -> Void = { _ in }

    private struct BoundWindow {
        var targetKey: String
        var displayUUID: String
        var spaceUUID: String
        var player: ScreenPlayer
        var bound: Bool
    }

    private var windows: [BoundWindow] = []
    private var observers: [NSObjectProtocol] = []

    var players: [ScreenPlayer] { windows.map(\.player) }

    func start(entryPath: String) {
        if SpaceBinding.readAssignments().targets.isEmpty {
            seedCurrentOnly(path: entryPath)
        }
        observe()
        reconcile()
    }

    func seedCurrentOnly(path: String) {
        guard MediaKind.from(path: path).usesSpaceBoundOverlay,
              FileManager.default.fileExists(atPath: path) else { return }
        let live = SpaceBinding.liveTargets()
        var file = PlaybackAssignmentFile(revision: 1, separateSpaces: live.separate, targets: [:])
        let kind = MediaKind.from(path: path)
        for target in live.targets where target.isCurrent {
            file.targets[target.key] = PlaybackAssignment(
                path: path,
                kind: kind.rawValue,
                paused: false,
                manualPause: false,
                pauseReason: nil
            )
        }
        guard !file.targets.isEmpty else { return }
        SpaceBinding.writeAssignments(file)
    }

    func spaceChanged() {
        reconcile()
    }

    func reconcile() {
        let assignments = SpaceBinding.readAssignments()
        let live = SpaceBinding.liveTargets()
        let facts = SpaceBinding.liveFacts()
        var desired: [(DesktopTarget, PlaybackAssignment)] = []
        for (key, assignment) in assignments.targets {
            guard let target = live.targets.first(where: { $0.key == key }) else { continue }
            let kind = MediaKind(rawValue: assignment.kind) ?? MediaKind.from(path: assignment.path)
            if kind.usesSpaceBoundOverlay, FileManager.default.fileExists(atPath: assignment.path) {
                desired.append((target, assignment))
            }
        }

        let desiredIDs = Set(desired.flatMap { target, _ in
            target.displayUUIDs.map { "\(target.key)#\($0)" }
        })
        windows.removeAll { window in
            let id = "\(window.targetKey)#\(window.displayUUID)"
            if desiredIDs.contains(id) { return false }
            window.player.clear()
            window.player.window.orderOut(nil)
            window.player.window.close()
            return true
        }

        var states: [String: PlaybackTargetState] = [:]
        for (target, assignment) in desired {
            var boundAll = !target.displayUUIDs.isEmpty
            var reasons: [String] = []
            var drawing = !target.displayUUIDs.isEmpty
            for displayUUID in target.displayUUIDs {
                guard let screen = SpaceBinding.screen(for: displayUUID),
                      let managedID = facts.first(where: {
                          $0.displayUUID == displayUUID && $0.spaceUUID == target.spaceUUID
                      })?.managedID else {
                    boundAll = false
                    drawing = false
                    reasons.append("space-bind-failed")
                    continue
                }
                let player = player(for: target.key, displayUUID: displayUUID, screen: screen)
                player.window.setFrame(screen.frame, display: true)
                if player.currentFilePath != assignment.path {
                    player.play(filePath: assignment.path, fade: false)
                } else if !player.window.isVisible {
                    player.window.orderFrontRegardless()
                }
                let bound = SpaceBinding.move(window: player.window, to: managedID)
                if let index = windows.firstIndex(where: { $0.targetKey == target.key && $0.displayUUID == displayUUID }) {
                    windows[index].bound = bound
                    windows[index].spaceUUID = target.spaceUUID
                }
                if !bound {
                    player.window.orderOut(nil)
                    boundAll = false
                    drawing = false
                    reasons.append("space-bind-failed")
                    continue
                }
                let reason = pauseReason(
                    assignment: assignment,
                    displayUUID: displayUUID,
                    spaceUUID: target.spaceUUID,
                    facts: facts
                )
                player.setDrawingPaused(reason != nil)
                if reason != nil { drawing = false }
                if let reason { reasons.append(reason) }
            }
            let reason = reasons.contains("space-bind-failed") ? "space-bind-failed" : reasons.first
            states[target.key] = PlaybackTargetState(
                path: assignment.path,
                playing: boundAll && drawing,
                paused: reason != nil,
                reason: reason,
                bound: boundAll
            )
        }

        SpaceBinding.writeState(PlaybackStateFile(updatedAt: Date(), targets: states))
        SpaceBinding.postState()
    }

    private func pauseReason(
        assignment: PlaybackAssignment,
        displayUUID: String,
        spaceUUID: String,
        facts: [SpaceFact]
    ) -> String? {
        if assignment.manualPause || assignment.pauseReason == "manual" { return "manual" }
        let fullscreen = facts.contains { $0.displayUUID == displayUUID && $0.type != 0 && $0.isCurrent }
        if fullscreen { return "fullscreen" }
        let visible = facts.contains {
            $0.displayUUID == displayUUID && $0.spaceUUID == spaceUUID && $0.isCurrent && $0.type == 0
        }
        if !visible { return "not-visible" }
        return nil
    }

    private func player(for targetKey: String, displayUUID: String, screen: NSScreen) -> ScreenPlayer {
        if let existing = windows.first(where: { $0.targetKey == targetKey && $0.displayUUID == displayUUID }) {
            return existing.player
        }
        let player = ScreenPlayer(screen: screen, isDaemon: true, joinsAllSpaces: false)
        configure(player)
        windows.append(BoundWindow(
            targetKey: targetKey,
            displayUUID: displayUUID,
            spaceUUID: "",
            player: player,
            bound: false
        ))
        return player
    }

    private func observe() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(
            forName: PlaybackNotices.reconcile,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconcile()
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.spaceChanged()
        })
    }
}
