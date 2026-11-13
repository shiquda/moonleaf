import AppKit
import Foundation

enum Check {
    static var failed = 0
    static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            failed += 1
            fputs("FAIL \(message)\n", stderr)
        }
    }
}

func session(key: String, path: String, kind: String, interval: String, last: Date?) -> TargetSession {
    TargetSession(
        targetKey: key,
        assetID: UUID(),
        assetName: "old",
        path: path,
        listKind: kind,
        playlistID: kind == "playlist" ? UUID() : nil,
        folderPath: nil,
        includeSubdirectories: nil,
        rotationEnabled: true,
        paused: false,
        pauseReason: nil,
        order: "sequential",
        interval: interval,
        unavailable: false,
        provenance: "moonleaf",
        lastRotatedAt: last
    )
}

@MainActor
@main
struct PlaybackChecks {
    static func main() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("moonleaf-playback-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        LibraryCatalog.fileURL = root.appendingPathComponent("catalog.json")
        let playback = PlaybackCoordinator.shared
        let previousShuffle = UserDefaults.standard.object(forKey: "moonleaf_shuffleEnabled")
        UserDefaults.standard.set(false, forKey: "moonleaf_shuffleEnabled")
        defer {
            if let previousShuffle {
                UserDefaults.standard.set(previousShuffle, forKey: "moonleaf_shuffleEnabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "moonleaf_shuffleEnabled")
            }
            SpaceBinding.factsOverride = nil
            SpaceWallpapers.spacesOverride = nil
            SpaceWallpapers.assignOverride = nil
            SpaceWallpapers.paintDesktopOverride = nil
            SpaceWallpapers.targetAssignmentsOverride = nil
            playback.libraryPoolOverride = nil
            playback.setCommandRefreshForChecks(false)
            SpaceBinding.stateReader = nil
            try? FileManager.default.removeItem(at: root)
        }

        testPlaylistAdd(playback)
        testTargetRefresh(playback)
        testOverlayCommit(playback)
        testListSchedule(playback)
        testConcurrentDueTargets(playback)
        testClearDropsLateReceipt(playback)
        testNewApplySupersedesReceipt(playback)
        testBindFailureRestoresEngine(playback)
        testStartupRecognizesDifferentMoonleafWallpapersPerDesktop(playback)
        testRandomWallpaperKeepsOtherDesktops(playback)
        testLibraryShuffleStopsAfterRandom(playback)
        testRandomVideoReceiptSummary(playback)
        testRandomReceiptArrivesBeforeNextApply(playback)
        testStatusTone()
        testDeferredStillPaintRevalidatesSpaceAndFailures(playback)

        if Check.failed == 0 {
            print("playback behavior checks passed")
        } else {
            fputs("\(Check.failed) checks failed\n", stderr)
            exit(1)
        }
    }

    /// A finished change must not look like a warning; a wait is a notice.
    static func testStatusTone() {
        Check.expect(
            PlaybackCoordinator.randomTone(["a": .applied, "b": .applied]) == .success,
            "a change that finished everywhere reads as success"
        )
        Check.expect(
            PlaybackCoordinator.randomTone(["a": .applied, "b": .pending]) == .info,
            "a pending receipt reads as a notice"
        )
        Check.expect(
            PlaybackCoordinator.randomTone(["a": .applied, "b": .failed]) == .warning,
            "a desktop left behind reads as a warning"
        )
        Check.expect(
            PlaybackCoordinator.randomTone(["a": .noSource]) == .warning,
            "a desktop without a source reads as a warning"
        )
    }

    static func testPlaylistAdd(_ playback: PlaybackCoordinator) {
        guard let id = playback.createPlaylist(name: "Review") else {
            Check.expect(false, "playlist was not created")
            return
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("moonleaf-add-\(UUID().uuidString).jpg")
        try? Data([0xFF, 0xD8, 0xFF]).write(to: file)
        playback.addToPlaylist(paths: [file.path], playlistID: id)
        let stored = playback.playlists.first { $0.id == id }
        Check.expect(stored?.assetIDs.count == 1, "adding to a playlist must not deadlock and must keep the asset")
        try? FileManager.default.removeItem(at: file)
    }

    static func testTargetRefresh(_ playback: PlaybackCoordinator) {
        Check.expect(
            PlaybackCoordinator.topologyWatch.contains(NSWorkspace.activeSpaceDidChangeNotification),
            "Space changes must refresh desktop identity"
        )
        let display = "DISPLAY-TEST"
        func facts(current: String) -> [SpaceFact] {
            ["space-a", "space-b"].map { space in
                SpaceFact(
                    displayUUID: display,
                    displayName: "Built-in",
                    spaceUUID: space,
                    managedID: space == "space-a" ? 3 : 4,
                    isCurrent: space == current,
                    type: 0
                )
            }
        }
        SpaceBinding.factsOverride = facts(current: "space-a")
        playback.refreshForCommand()
        Check.expect(playback.currentTarget(displayUUID: display)?.spaceUUID == "space-a", "first space is current")
        SpaceBinding.factsOverride = facts(current: "space-b")
        Check.expect(playback.currentTarget(displayUUID: display)?.spaceUUID == "space-a", "cached identity stays stale until refresh")
        playback.refreshForCommand()
        Check.expect(playback.currentTarget(displayUUID: display)?.spaceUUID == "space-b", "refresh follows the live Space")
    }

    static func testOverlayCommit(_ playback: PlaybackCoordinator) {
        let key = "d:DISPLAY-TEST|s:space-b"
        LibraryCatalog.shared.mutate { file in
            file.sessions = [session(key: key, path: "/old.jpg", kind: "library", interval: "5", last: nil)]
            file.history = []
        }
        playback.reloadForChecks()
        let when = Date(timeIntervalSince1970: 1_700_000_100)
        let request = "request-1"
        let listID = UUID()
        func pendingRequest() -> PendingOverlay {
            PendingOverlay(
                requestID: request,
                requestedAt: when,
                path: "/new.mp4",
                assetID: UUID(),
                assetName: "new",
                keys: [key],
                origin: "manual",
                playlistID: listID,
                playlistName: "Review",
                recordHistory: true,
                stopRotation: false,
                stamp: ListStamp(
                    kind: "playlist",
                    playlistID: listID,
                    playlistName: "Review",
                    order: "sequential",
                    interval: "1",
                    folderPath: nil,
                    includeSubdirectories: nil,
                    rotationEnabled: true
                ),
                touchRotationClock: false
            )
        }
        playback.pendingByTarget[key] = pendingRequest()
        playback.acceptReported(PlaybackStateFile(
            updatedAt: when,
            targets: [key: PlaybackTargetState(
                path: "/new.mp4", playing: true, paused: false, reason: nil, bound: true,
                requestID: "other", requestedAt: when
            )]
        ))
        Check.expect(playback.history.isEmpty, "unrelated state must not record history")
        Check.expect(playback.sessions.first?.path == "/old.jpg", "unrelated state must not switch the session")
        Check.expect(playback.pendingByTarget[key] != nil, "unrelated state leaves the request open")

        playback.acceptReported(PlaybackStateFile(
            updatedAt: when,
            targets: [key: PlaybackTargetState(
                path: "/new.mp4", playing: false, paused: true, reason: "space-bind-failed", bound: false,
                requestID: request, requestedAt: when
            )]
        ))
        Check.expect(playback.history.isEmpty, "bind failure must not record history")
        Check.expect(playback.sessions.first?.path == "/old.jpg", "bind failure must not switch the list")
        Check.expect(playback.pendingByTarget.isEmpty, "bind failure closes the request")
        Check.expect(playback.statusMessage == NSLocalizedString("bind_failed", comment: ""), "bind failure is reported")

        playback.pendingByTarget[key] = pendingRequest()
        playback.acceptReported(PlaybackStateFile(
            updatedAt: when.addingTimeInterval(1),
            targets: [key: PlaybackTargetState(
                path: "/new.mp4", playing: false, paused: true, reason: "not-visible", bound: true,
                requestID: request, requestedAt: when
            )]
        ))
        Check.expect(playback.history.count == 1, "matching bound state records one success")
        Check.expect(playback.sessions.first?.path == "/new.mp4", "matching state commits the new path")
        Check.expect(playback.sessions.first?.playlistID == listID, "matching state switches the list")
        Check.expect(playback.pendingByTarget.isEmpty, "success closes the request")
    }

    static func testListSchedule(_ playback: PlaybackCoordinator) {
        playback.reloadForChecks()
        let now = Date()
        LibraryCatalog.shared.mutate { file in
            file.sessions = [session(
                key: "d:DISPLAY-TEST|s:space-b",
                path: "/missing-list.mp4",
                kind: "playlist",
                interval: "60",
                last: now
            )]
        }
        playback.rotateDueSessions(now: now.addingTimeInterval(30))
        Check.expect(playback.statusMessage == nil, "a list inside its own interval does not advance")

        LibraryCatalog.shared.mutate { file in
            file.sessions = [session(
                key: "d:DISPLAY-TEST|s:space-b",
                path: "/missing-list.mp4",
                kind: "playlist",
                interval: "1",
                last: now.addingTimeInterval(-120)
            )]
        }
        playback.rotateDueSessions(now: now)
        Check.expect(
            playback.statusMessage == NSLocalizedString("list_empty", comment: ""),
            "a due named list advances even when library shuffle is off"
        )
    }

    static func testConcurrentDueTargets(_ playback: PlaybackCoordinator) {
        let display = "DISPLAY-DUE"
        SpaceBinding.factsOverride = ["space-a", "space-b"].map { space in
            SpaceFact(
                displayUUID: display,
                displayName: "Built-in",
                spaceUUID: space,
                managedID: space == "space-a" ? 3 : 4,
                isCurrent: false,
                type: 0
            )
        }
        playback.refreshForCommand()
        let keyA = "d:\(display)|s:space-a"
        let keyB = "d:\(display)|s:space-b"
        let fileA = FileManager.default.temporaryDirectory.appendingPathComponent("moonleaf-due-a-\(UUID().uuidString).mp4")
        let fileB = FileManager.default.temporaryDirectory.appendingPathComponent("moonleaf-due-b-\(UUID().uuidString).mp4")
        try? Data().write(to: fileA)
        try? Data().write(to: fileB)
        defer {
            try? FileManager.default.removeItem(at: fileA)
            try? FileManager.default.removeItem(at: fileB)
        }
        guard let listA = playback.createPlaylist(name: "Due A"),
              let listB = playback.createPlaylist(name: "Due B") else {
            Check.expect(false, "due playlists were not created")
            return
        }
        playback.addToPlaylist(paths: [fileA.path], playlistID: listA)
        playback.addToPlaylist(paths: [fileB.path], playlistID: listB)
        let now = Date()
        LibraryCatalog.shared.mutate { file in
            file.sessions = [
                session(key: keyA, path: fileA.path, kind: "playlist", interval: "1", last: now.addingTimeInterval(-120)),
                session(key: keyB, path: fileB.path, kind: "playlist", interval: "1", last: now.addingTimeInterval(-120)),
            ]
            file.sessions[0].playlistID = listA
            file.sessions[1].playlistID = listB
        }
        playback.pendingByTarget = [:]
        playback.rotateDueSessions(now: now)
        let pendingA = playback.pendingByTarget[keyA]
        let pendingB = playback.pendingByTarget[keyB]
        Check.expect(pendingA != nil && pendingB != nil, "both due desktops keep a request")
        Check.expect(pendingA?.requestID != pendingB?.requestID, "each desktop has its own request")
        let pathA = pendingA?.path
        let pathB = pendingB?.path
        Check.expect(
            pathA != pathB
                && pathA.map { FileManager.default.fileExists(atPath: $0) } == true
                && pathB.map { FileManager.default.fileExists(atPath: $0) } == true,
            "neither request is replaced by the other"
        )
        let firstA = pendingA?.requestID
        playback.rotateDueSessions(now: now)
        Check.expect(playback.pendingByTarget[keyA]?.requestID == firstA, "a second tick does not drop the first open request")
    }

    static func testClearDropsLateReceipt(_ playback: PlaybackCoordinator) {
        let key = "d:DISPLAY-TEST|s:space-b"
        let when = Date(timeIntervalSince1970: 1_700_000_200)
        let request = "cleared-request"
        LibraryCatalog.shared.mutate { file in
            file.sessions = [session(key: key, path: "/old.jpg", kind: "library", interval: "5", last: nil)]
            file.history = []
        }
        playback.reloadForChecks()
        playback.pendingByTarget[key] = PendingOverlay(
            requestID: request,
            requestedAt: when,
            path: "/new.mp4",
            assetID: UUID(),
            assetName: "new",
            keys: [key],
            origin: "manual",
            playlistID: nil,
            playlistName: nil,
            recordHistory: true,
            stopRotation: false,
            stamp: nil,
            touchRotationClock: false
        )
        playback.clearTarget(key)
        Check.expect(playback.pendingByTarget[key] == nil, "clear drops the open request")
        Check.expect(!playback.sessions.contains { $0.targetKey == key }, "clear removes the session")
        playback.acceptReported(PlaybackStateFile(
            updatedAt: when.addingTimeInterval(1),
            targets: [key: PlaybackTargetState(
                path: "/new.mp4", playing: true, paused: false, reason: nil, bound: true,
                requestID: request, requestedAt: when
            )]
        ))
        Check.expect(!playback.sessions.contains { $0.targetKey == key }, "a late receipt does not revive a cleared desktop")
        Check.expect(playback.history.isEmpty, "a late receipt does not record history")
    }

    static func testNewApplySupersedesReceipt(_ playback: PlaybackCoordinator) {
        let display = "DISPLAY-RACE"
        let space = "space-race"
        let key = "d:\(display)|s:\(space)"
        SpaceBinding.factsOverride = [SpaceFact(
            displayUUID: display,
            displayName: "Built-in",
            spaceUUID: space,
            managedID: 9,
            isCurrent: false,
            type: 0
        )]
        playback.refreshForCommand()
        let first = FileManager.default.temporaryDirectory.appendingPathComponent("moonleaf-race-a-\(UUID().uuidString).mp4")
        let second = FileManager.default.temporaryDirectory.appendingPathComponent("moonleaf-race-b-\(UUID().uuidString).mp4")
        let still = FileManager.default.temporaryDirectory.appendingPathComponent("moonleaf-race-\(UUID().uuidString).jpg")
        try? Data().write(to: first)
        try? Data().write(to: second)
        try? Data([0xFF, 0xD8, 0xFF]).write(to: still)
        SpaceWallpapers.spacesOverride = [SpaceWallpapers.Space(displayUUID: display, uuid: space, isCurrent: false)]
        SpaceWallpapers.assignOverride = { _ in true }
        defer {
            SpaceWallpapers.spacesOverride = nil
            SpaceWallpapers.assignOverride = nil
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
            try? FileManager.default.removeItem(at: still)
        }
        Check.expect(!playback.apply(
            path: first.path, name: "first", scope: .explicit, displayUUID: display,
            explicitKeys: [key], stopRotation: true, origin: "manual",
            confirmedCrossDisplay: true, recordHistory: true
        ), "first video waits for the engine")
        let firstID = playback.pendingByTarget[key]?.requestID
        Check.expect(firstID != nil, "first video is pending")
        Check.expect(!playback.apply(
            path: second.path, name: "second", scope: .explicit, displayUUID: display,
            explicitKeys: [key], stopRotation: true, origin: "manual",
            confirmedCrossDisplay: true, recordHistory: true
        ), "second video waits for the engine")
        let secondID = playback.pendingByTarget[key]?.requestID
        Check.expect(secondID != nil && secondID != firstID, "the new video replaces the open request")
        let when = Date()
        playback.acceptReported(PlaybackStateFile(
            updatedAt: when,
            targets: [key: PlaybackTargetState(
                path: first.path, playing: true, paused: false, reason: nil, bound: true,
                requestID: firstID ?? "", requestedAt: when
            )]
        ))
        Check.expect(playback.sessions.allSatisfy { $0.path != first.path }, "the old receipt does not commit the replaced video")
        Check.expect(playback.pendingByTarget[key]?.requestID == secondID, "the new request stays open")
        Check.expect(playback.apply(
            path: still.path, name: "still", scope: .explicit, displayUUID: display,
            explicitKeys: [key], stopRotation: true, origin: "manual",
            confirmedCrossDisplay: true, recordHistory: true
        ), "a still on a hidden desktop commits without painting the visible screen")
        Check.expect(playback.pendingByTarget[key] == nil, "a committed still drops the open video request")
        Check.expect(playback.sessions.first { $0.targetKey == key }?.path == still.path, "the still is the committed wallpaper")
        playback.acceptReported(PlaybackStateFile(
            updatedAt: when.addingTimeInterval(1),
            targets: [key: PlaybackTargetState(
                path: second.path, playing: true, paused: false, reason: nil, bound: true,
                requestID: secondID ?? "", requestedAt: when
            )]
        ))
        Check.expect(playback.sessions.first { $0.targetKey == key }?.path == still.path, "a late video receipt does not replace the still")
    }

    static func testBindFailureRestoresEngine(_ playback: PlaybackCoordinator) {
        let key = "d:DISPLAY-ROLLBACK|s:space-a"
        let old = FileManager.default.temporaryDirectory.appendingPathComponent("moonleaf-rollback-old-\(UUID().uuidString).mp4")
        let rejected = FileManager.default.temporaryDirectory.appendingPathComponent("moonleaf-rollback-new-\(UUID().uuidString).mp4")
        try? Data().write(to: old)
        try? Data().write(to: rejected)
        var captured: [PlaybackAssignmentFile] = []
        playback.assignmentsSink = { captured.append($0) }
        defer {
            playback.assignmentsSink = nil
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.removeItem(at: rejected)
        }
        LibraryCatalog.shared.mutate { file in
            file.sessions = [session(key: key, path: old.path, kind: "library", interval: "5", last: nil)]
            file.history = []
        }
        playback.reloadForChecks()
        let when = Date()
        let request = PendingOverlay(
            requestID: "rejected-request",
            requestedAt: when,
            path: rejected.path,
            assetID: UUID(),
            assetName: "rejected",
            keys: [key],
            origin: "manual",
            playlistID: nil,
            playlistName: nil,
            recordHistory: true,
            stopRotation: true,
            stamp: nil,
            touchRotationClock: false
        )
        playback.pendingByTarget[key] = request
        captured = []
        playback.acceptReported(PlaybackStateFile(
            updatedAt: when.addingTimeInterval(1),
            targets: [key: PlaybackTargetState(
                path: rejected.path, playing: false, paused: true,
                reason: "space-bind-failed", bound: false,
                requestID: request.requestID, requestedAt: when
            )]
        ))
        Check.expect(playback.pendingByTarget[key] == nil, "a failed request is closed")
        Check.expect(playback.sessions.first { $0.targetKey == key }?.path == old.path, "a failed request keeps the old session")
        Check.expect(captured.last != nil, "a failed request republishes the assignment file")
        Check.expect(captured.last?.targets[key]?.path == old.path, "the engine is told to restore the old wallpaper")
        Check.expect(captured.last?.targets[key]?.requestID != request.requestID, "the engine no longer holds the rejected request")

        LibraryCatalog.shared.mutate { $0.sessions = [] }
        playback.reloadForChecks()
        let second = PendingOverlay(
            requestID: "rejected-again",
            requestedAt: when,
            path: rejected.path,
            assetID: UUID(),
            assetName: "rejected",
            keys: [key],
            origin: "manual",
            playlistID: nil,
            playlistName: nil,
            recordHistory: true,
            stopRotation: true,
            stamp: nil,
            touchRotationClock: false
        )
        playback.pendingByTarget[key] = second
        captured = []
        playback.acceptReported(PlaybackStateFile(
            updatedAt: when.addingTimeInterval(1),
            targets: [key: PlaybackTargetState(
                path: rejected.path, playing: false, paused: true,
                reason: "space-bind-failed", bound: false,
                requestID: second.requestID, requestedAt: when
            )]
        ))
        Check.expect(playback.pendingByTarget[key] == nil, "a failed request without a previous wallpaper is closed")
        Check.expect(captured.last != nil, "a failed request without a previous wallpaper republishes the assignment file")
        Check.expect(captured.last?.targets.keys.contains(key) == false, "a failed target with no previous wallpaper leaves the engine file")
    }

    static func testStartupRecognizesDifferentMoonleafWallpapersPerDesktop(_ playback: PlaybackCoordinator) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("moonleaf-seed-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let wp1 = dir.appendingPathComponent("one.jpg")
        let wp2 = dir.appendingPathComponent("two.jpg")
        let wp3 = dir.appendingPathComponent("three.jpg")
        let systemWP = dir.appendingPathComponent("system.heic")
        let externalNonMoonleaf = FileManager.default.temporaryDirectory.appendingPathComponent("other-\(UUID().uuidString).jpg")
        for url in [wp1, wp2, wp3, systemWP, externalNonMoonleaf] {
            try? Data([0xFF, 0xD8, 0xFF]).write(to: url)
        }
        defer {
            SpaceBinding.factsOverride = nil
            SpaceWallpapers.targetAssignmentsOverride = nil
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: externalNonMoonleaf)
        }

        let staleKey = "d:OLD-DISPLAY|s:old-space"
        LibraryCatalog.shared.mutate { file in
            file.assets = []
            file.sessions = [session(key: staleKey, path: wp1.path, kind: "library", interval: "5", last: nil)]
            file.history = []
            file.suppressedRestoreKeys = []
            file.futureSaveDirectory = dir.path
        }
        playback.reloadForChecks()

        let k1 = "d:DISP-A|s:space-1"
        let k2 = "d:DISP-A|s:space-2"
        let k3 = "d:DISP-B|s:space-3"
        let k4 = "d:DISP-B|s:space-4"
        SpaceBinding.factsOverride = [
            SpaceFact(displayUUID: "DISP-A", displayName: "A", spaceUUID: "space-1", managedID: 10, isCurrent: true, type: 0),
            SpaceFact(displayUUID: "DISP-A", displayName: "A", spaceUUID: "space-2", managedID: 11, isCurrent: false, type: 0),
            SpaceFact(displayUUID: "DISP-B", displayName: "B", spaceUUID: "space-3", managedID: 12, isCurrent: true, type: 0),
            SpaceFact(displayUUID: "DISP-B", displayName: "B", spaceUUID: "space-4", managedID: 13, isCurrent: false, type: 0),
        ]
        SpaceWallpapers.targetAssignmentsOverride = { targets in
            var map: [String: String] = [:]
            for t in targets {
                switch t.key {
                case k1: map[t.key] = wp1.path
                case k2: map[t.key] = wp2.path
                case k3: map[t.key] = wp3.path
                case k4: map[t.key] = externalNonMoonleaf.path
                default: break
                }
            }
            return map
        }

        playback.refreshTopology(restoreMatching: false)

        Check.expect(playback.session(for: k1)?.path == wp1.path, "display A space 1 wallpaper recognized despite stale unavailable session")
        Check.expect(playback.session(for: k2)?.path == wp2.path, "display A space 2 wallpaper recognized independently")
        Check.expect(playback.session(for: k3)?.path == wp3.path, "display B space 3 wallpaper recognized independently")
        Check.expect(playback.session(for: k4) == nil, "non-moonleaf wallpaper must not be claimed automatically")
        Check.expect(playback.session(for: staleKey)?.unavailable == true, "stale disconnected session stays unavailable")
        Check.expect(playback.history.isEmpty, "auto-recognition on startup must not add history events")

        // Clearing a recognized desktop must suppress auto-resurrection on subsequent topology refreshes
        playback.clearTarget(k2)
        Check.expect(playback.session(for: k2) == nil, "cleared target has no session")
        playback.refreshTopology(restoreMatching: false)
        Check.expect(playback.session(for: k2) == nil, "cleared target stays unset instead of resurrecting")
    }

    static func testRandomWallpaperKeepsOtherDesktops(_ playback: PlaybackCoordinator) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("moonleaf-random-\(UUID().uuidString)", isDirectory: true)
        let folder = dir.appendingPathComponent("only", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let a = dir.appendingPathComponent("a.jpg")
        let b = dir.appendingPathComponent("b.jpg")
        let c = dir.appendingPathComponent("c.jpg")
        let only = folder.appendingPathComponent("only.jpg")
        for url in [a, b, c, only] {
            try? Data([0xFF, 0xD8, 0xFF]).write(to: url)
        }
        defer {
            SpaceBinding.factsOverride = nil
            SpaceWallpapers.spacesOverride = nil
            SpaceWallpapers.assignOverride = nil
            try? FileManager.default.removeItem(at: dir)
        }
        guard let listID = playback.createPlaylist(name: "Desk") else {
            Check.expect(false, "random playlist was not created")
            return
        }
        playback.addToPlaylist(paths: [a.path, b.path, c.path], playlistID: listID)
        let assets = LibraryCatalog.shared.snapshot().assets
        func asset(_ suffix: String) -> AssetRecord? {
            assets.first { $0.path.hasSuffix(suffix) }
        }
        guard let assetA = asset("a.jpg"), let assetC = asset("c.jpg") else {
            Check.expect(false, "playlist assets were not saved")
            return
        }

        SpaceBinding.factsOverride = [
            SpaceFact(displayUUID: "DISP-A", displayName: "Built-in", spaceUUID: "space-1", managedID: 21, isCurrent: false, type: 0),
            SpaceFact(displayUUID: "DISP-A", displayName: "Built-in", spaceUUID: "space-2", managedID: 22, isCurrent: false, type: 0),
        ]
        SpaceWallpapers.spacesOverride = [
            SpaceWallpapers.Space(displayUUID: "DISP-A", uuid: "space-1", isCurrent: false),
            SpaceWallpapers.Space(displayUUID: "DISP-A", uuid: "space-2", isCurrent: false),
        ]
        SpaceWallpapers.targetAssignmentsOverride = { _ in [:] }
        SpaceWallpapers.assignOverride = { _ in true }
        playback.refreshTopology(restoreMatching: false)
        guard let first = playback.targets.first(where: { $0.spaceUUID == "space-1" }),
              let second = playback.targets.first(where: { $0.spaceUUID == "space-2" }) else {
            Check.expect(false, "test desktops were not recognized")
            return
        }
        let k1 = first.key
        let k2 = second.key
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        guard let onlyList = playback.createPlaylist(name: "Only") else {
            Check.expect(false, "single-item playlist was not created")
            return
        }
        playback.addToPlaylist(paths: [only.path], playlistID: onlyList)
        guard let onlyAsset = LibraryCatalog.shared.snapshot().assets.first(where: { $0.path.hasSuffix("only.jpg") }) else {
            Check.expect(false, "single wallpaper was not saved")
            return
        }
        LibraryCatalog.shared.mutate { file in
            file.history = []
            file.sessions = [
                TargetSession(
                    targetKey: k1, assetID: assetA.id, assetName: assetA.name, path: assetA.path,
                    listKind: "playlist", playlistID: listID, folderPath: nil, includeSubdirectories: nil,
                    rotationEnabled: true, paused: true, pauseReason: "manual", order: "sequential",
                    interval: "60", unavailable: false, provenance: "moonleaf", lastRotatedAt: when
                ),
                TargetSession(
                    targetKey: k2, assetID: onlyAsset.id, assetName: onlyAsset.name, path: onlyAsset.path,
                    listKind: "playlist", playlistID: onlyList, folderPath: nil, includeSubdirectories: nil,
                    rotationEnabled: false, paused: false, pauseReason: nil, order: "random",
                    interval: "5", unavailable: false, provenance: "moonleaf", lastRotatedAt: nil
                ),
            ]
        }
        playback.reloadForChecks()
        playback.pendingByTarget = [:]

        let one = playback.randomWallpaper(keys: [k1]) { _ in 1 }
        Check.expect(one[k1] == .applied, "one desktop can change, got \(String(describing: one[k1])) \(playback.statusMessage ?? "") keys \(playback.targets.map(\.key))")
        Check.expect(playback.session(for: k1)?.path?.hasSuffix("c.jpg") == true, "random does not walk the list in order, got \(playback.session(for: k1)?.path ?? "nil")")
        Check.expect(playback.session(for: k2)?.path == onlyAsset.path, "a one-desktop shuffle leaves the other desktop")
        Check.expect(playback.session(for: k1)?.paused == true, "a paused desktop stays paused")
        Check.expect(playback.session(for: k1)?.pauseReason == "manual", "manual pause reason stays")
        Check.expect(playback.session(for: k1)?.playlistID == listID, "shuffle does not switch the playlist")
        Check.expect(playback.session(for: k1)?.rotationEnabled == true, "shuffle does not turn rotation off")
        Check.expect(playback.session(for: k1)?.order == "sequential", "shuffle does not change list order")
        Check.expect(playback.session(for: k1)?.interval == "60", "shuffle does not change the interval")
        Check.expect(playback.session(for: k1)?.lastRotatedAt == when, "a paused desktop does not restart the rotation clock")
        Check.expect(playback.history.count == 1, "only the successful desktop is recorded")
        Check.expect(playback.history.last?.targetKeys == [k1], "history names the desktop that changed")

        let both = playback.randomWallpaper(keys: [k1, k2]) { _ in 0 }
        Check.expect(both[k2] == .noOther, "a desktop with only its current wallpaper is not changed")
        Check.expect(playback.session(for: k2)?.path == onlyAsset.path, "no other wallpaper keeps the old file")
        Check.expect(playback.history.filter { $0.targetKeys == [k2] }.isEmpty, "a no-op does not write history")
        Check.expect(both[k1] == .applied, "the other desktop still changes on its own")
        Check.expect(playback.session(for: k1)?.path != assetC.path, "each desktop picks independently")

        let beforeFail = playback.history.count
        let kept = playback.session(for: k1)?.path
        SpaceWallpapers.assignOverride = { _ in false }
        let failed = playback.randomWallpaper(keys: [k1, k2]) { _ in 0 }
        Check.expect(failed[k1] == .failed, "a rejected write is a failure")
        Check.expect(playback.session(for: k1)?.path == kept, "a failed desktop keeps its wallpaper")
        Check.expect(playback.history.count == beforeFail, "a failed change is not a successful history event")
        Check.expect(failed[k2] == .noOther, "a failed neighbor does not invent a change")
    }

    static func testLibraryShuffleStopsAfterRandom(_ playback: PlaybackCoordinator) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moonleaf-library-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let first = dir.appendingPathComponent("a.jpg")
        let second = dir.appendingPathComponent("b.jpg")
        for url in [first, second] {
            try? Data([0xFF, 0xD8, 0xFF]).write(to: url)
        }
        defer {
            playback.libraryPoolOverride = nil
            UserDefaults.standard.set(false, forKey: "moonleaf_shuffleEnabled")
            SpaceBinding.factsOverride = nil
            SpaceWallpapers.spacesOverride = nil
            SpaceWallpapers.assignOverride = nil
            try? FileManager.default.removeItem(at: dir)
        }
        playback.libraryPoolOverride = dir.path
        let listed = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .map(\.path).sorted() ?? []
        guard listed.count == 2 else {
            Check.expect(false, "library files were not listed, got \(listed)")
            return
        }
        let assetA = LibraryCatalog.shared.ensureAsset(path: listed[0], name: "a", source: "library", origin: nil)
        let assetB = LibraryCatalog.shared.ensureAsset(path: listed[1], name: "b", source: "library", origin: nil)
        SpaceBinding.factsOverride = [
            SpaceFact(displayUUID: "DISP-A", displayName: "Built-in", spaceUUID: "space-lib", managedID: 31, isCurrent: false, type: 0),
        ]
        SpaceWallpapers.spacesOverride = [
            SpaceWallpapers.Space(displayUUID: "DISP-A", uuid: "space-lib", isCurrent: false),
        ]
        SpaceWallpapers.assignOverride = { _ in true }
        playback.refreshTopology(restoreMatching: false)
        guard let key = playback.targets.first(where: { $0.spaceUUID == "space-lib" })?.key else {
            Check.expect(false, "library desktop was not recognized")
            return
        }
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        LibraryCatalog.shared.mutate { file in
            file.history = []
            file.sessions = [
                TargetSession(
                    targetKey: key, assetID: assetA.id, assetName: assetA.name, path: assetA.path,
                    listKind: nil, playlistID: nil, folderPath: nil, includeSubdirectories: nil,
                    rotationEnabled: false, paused: false, pauseReason: nil, order: "sequential",
                    interval: "1", unavailable: false, provenance: "moonleaf", lastRotatedAt: when
                ),
            ]
        }
        playback.reloadForChecks()
        playback.pendingByTarget = [:]
        UserDefaults.standard.set(false, forKey: "moonleaf_shuffleEnabled")

        let picked = playback.randomWallpaper(keys: [key]) { _ in 0 }
        Check.expect(picked[key] == .applied, "a library shuffle changes the desktop, got \(String(describing: picked[key])) \(playback.statusMessage ?? "")")
        Check.expect(playback.session(for: key)?.path == assetB.path, "library shuffle picks the other file, got \(playback.session(for: key)?.path ?? "nil")")
        Check.expect(playback.session(for: key)?.listKind == nil, "a library shuffle keeps the nil source, got \(playback.session(for: key)?.listKind ?? "nil")")
        Check.expect(playback.session(for: key)?.rotationEnabled == false, "a library shuffle does not turn rotation on")
        let afterRandom = playback.history.count

        SpaceBinding.factsOverride = [
            SpaceFact(displayUUID: "DISP-A", displayName: "Built-in", spaceUUID: "space-lib", managedID: 31, isCurrent: true, type: 0),
        ]
        playback.refreshTopology(restoreMatching: false)
        playback.enableRotationOnCurrentDesktop()
        Check.expect(playback.session(for: key)?.rotationEnabled == true, "the desktop rotation can be turned on after a library shuffle")
        Check.expect(playback.session(for: key)?.listKind == "library", "turning rotation on keeps a library source, got \(playback.session(for: key)?.listKind ?? "nil")")
        SpaceBinding.factsOverride = [
            SpaceFact(displayUUID: "DISP-A", displayName: "Built-in", spaceUUID: "space-lib", managedID: 31, isCurrent: false, type: 0),
        ]
        playback.refreshTopology(restoreMatching: false)
        LibraryCatalog.shared.mutate { file in
            guard let index = file.sessions.firstIndex(where: { $0.targetKey == key }) else { return }
            file.sessions[index].lastRotatedAt = when
        }
        playback.reloadForChecks()
        playback.rotateDueSessions(now: when.addingTimeInterval(120))
        Check.expect(playback.session(for: key)?.path == assetB.path, "library rotation off keeps the shuffled wallpaper")
        Check.expect(playback.history.count == afterRandom, "library rotation off does not record another success")

        UserDefaults.standard.set(true, forKey: "moonleaf_shuffleEnabled")
        playback.rotateDueSessions(now: when.addingTimeInterval(180))
        Check.expect(playback.session(for: key)?.path == assetA.path, "library rotation on still advances, got \(playback.session(for: key)?.path ?? "nil")")
        Check.expect(playback.history.count == afterRandom + 1, "library rotation on records the automatic change")

        UserDefaults.standard.set(false, forKey: "moonleaf_shuffleEnabled")
        LibraryCatalog.shared.mutate { file in
            guard let index = file.sessions.firstIndex(where: { $0.targetKey == key }) else { return }
            file.sessions[index].listKind = ""
            file.sessions[index].lastRotatedAt = when
        }
        playback.reloadForChecks()
        let beforeBlank = playback.history.count
        let blankPath = playback.session(for: key)?.path
        playback.rotateDueSessions(now: when.addingTimeInterval(240))
        Check.expect(playback.session(for: key)?.path == blankPath, "a blank source does not bypass the library switch")
        Check.expect(playback.history.count == beforeBlank, "a blank source does not record a success while library rotation is off")

    }

    static func testRandomVideoReceiptSummary(_ playback: PlaybackCoordinator) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("moonleaf-video-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let files = ["a.mp4", "b.mp4", "c.mp4", "d.mp4"].map { dir.appendingPathComponent($0) }
        for url in files {
            try? Data([0x00, 0x00, 0x00, 0x18]).write(to: url)
        }
        defer {
            playback.assignmentsSink = nil
            playback.pendingByTarget = [:]
            _ = playback.randomWallpaper(keys: [])
            SpaceBinding.factsOverride = nil
            SpaceWallpapers.spacesOverride = nil
            try? FileManager.default.removeItem(at: dir)
        }
        guard let listA = playback.createPlaylist(name: "Video A"),
              let listB = playback.createPlaylist(name: "Video B") else {
            Check.expect(false, "video playlists were not created")
            return
        }
        playback.addToPlaylist(paths: [files[0].path, files[1].path], playlistID: listA)
        playback.addToPlaylist(paths: [files[2].path, files[3].path], playlistID: listB)
        func asset(_ suffix: String) -> AssetRecord? {
            LibraryCatalog.shared.snapshot().assets.first { $0.path.hasSuffix(suffix) }
        }
        guard let assetA = asset("a.mp4"), let assetC = asset("c.mp4") else {
            Check.expect(false, "video assets were not saved")
            return
        }
        SpaceBinding.factsOverride = [
            SpaceFact(displayUUID: "DISP-A", displayName: "Built-in", spaceUUID: "space-v1", managedID: 41, isCurrent: false, type: 0),
            SpaceFact(displayUUID: "DISP-A", displayName: "Built-in", spaceUUID: "space-v2", managedID: 42, isCurrent: false, type: 0),
        ]
        playback.refreshTopology(restoreMatching: false)
        guard let first = playback.targets.first(where: { $0.spaceUUID == "space-v1" }),
              let second = playback.targets.first(where: { $0.spaceUUID == "space-v2" }) else {
            Check.expect(false, "video desktops were not recognized")
            return
        }
        let k1 = first.key
        let k2 = second.key
        LibraryCatalog.shared.mutate { file in
            file.history = []
            file.sessions = [
                TargetSession(
                    targetKey: k1, assetID: assetA.id, assetName: assetA.name, path: assetA.path,
                    listKind: "playlist", playlistID: listA, folderPath: nil, includeSubdirectories: nil,
                    rotationEnabled: false, paused: true, pauseReason: "manual", order: "random",
                    interval: "5", unavailable: false, provenance: "moonleaf", lastRotatedAt: nil
                ),
                TargetSession(
                    targetKey: k2, assetID: assetC.id, assetName: assetC.name, path: assetC.path,
                    listKind: "playlist", playlistID: listB, folderPath: nil, includeSubdirectories: nil,
                    rotationEnabled: false, paused: false, pauseReason: nil, order: "random",
                    interval: "5", unavailable: false, provenance: "moonleaf", lastRotatedAt: nil
                ),
            ]
        }
        playback.reloadForChecks()
        playback.pendingByTarget = [:]
        playback.assignmentsSink = { _ in }
        let report = playback.randomWallpaper(keys: [k1, k2]) { _ in 0 }
        Check.expect(report[k1] == .pending && report[k2] == .pending, "video shuffles wait for the engine, got \(report)")
        Check.expect(playback.history.isEmpty, "a waiting video shuffle is not a successful history event")
        func label(_ target: DesktopTarget) -> String {
            "\(target.displayName) \(String(format: NSLocalizedString("desktop_n", comment: ""), target.spaceIndex))"
        }
        let waiting = String(format: NSLocalizedString("random_waiting", comment: ""), [label(first), label(second)].joined(separator: ", "))
        Check.expect(playback.statusMessage == waiting, "waiting is not reported as changed, got \(playback.statusMessage ?? "nil")")
        Check.expect(playback.statusMessage != String(format: NSLocalizedString("random_done", comment: ""), 2), "two pending videos are not two successes")

        guard let pendingA = playback.pendingByTarget[k1], let pendingB = playback.pendingByTarget[k2] else {
            Check.expect(false, "video requests were not stored")
            return
        }
        playback.acceptReported(PlaybackStateFile(
            updatedAt: Date(),
            targets: [
                k1: PlaybackTargetState(
                    path: pendingA.path, playing: false, paused: true, reason: nil, bound: true,
                    requestID: pendingA.requestID, requestedAt: pendingA.requestedAt
                ),
                k2: PlaybackTargetState(
                    path: pendingB.path, playing: false, paused: true, reason: "space-bind-failed", bound: false,
                    requestID: pendingB.requestID, requestedAt: pendingB.requestedAt
                ),
            ]
        ))
        Check.expect(playback.history.count == 1, "only the confirmed video is recorded, got \(playback.history.count)")
        Check.expect(playback.history.last?.targetKeys == [k1], "history names the desktop that confirmed")
        Check.expect(playback.session(for: k1)?.path?.hasSuffix("b.mp4") == true, "the confirmed desktop changes")
        Check.expect(playback.session(for: k1)?.paused == true, "a paused video stays paused after confirmation")
        Check.expect(playback.session(for: k2)?.path == assetC.path, "a failed bind keeps the old wallpaper")
        Check.expect(playback.history.contains { $0.targetKeys.contains(k2) } == false, "a failed bind is not a success")
        let done = String(format: NSLocalizedString("random_done", comment: ""), 1)
        let failed = String(format: NSLocalizedString("random_failed_targets", comment: ""), label(second))
        Check.expect(playback.statusMessage == "\(done) \(failed)", "the final note names success and failure, got \(playback.statusMessage ?? "nil")")
        Check.expect(playback.statusMessage != NSLocalizedString("bind_failed", comment: ""), "a partial shuffle does not collapse to a generic bind failure")
    }

    static func testRandomReceiptArrivesBeforeNextApply(_ playback: PlaybackCoordinator) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("moonleaf-early-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let files = ["a.mp4", "b.mp4", "c.mp4", "d.mp4"].map { dir.appendingPathComponent($0) }
        for url in files {
            try? Data([0x00, 0x00, 0x00, 0x18]).write(to: url)
        }
        defer {
            playback.setCommandRefreshForChecks(false)
            playback.assignmentsSink = nil
            playback.pendingByTarget = [:]
            SpaceBinding.stateReader = nil
            SpaceBinding.factsOverride = nil
            try? FileManager.default.removeItem(at: dir)
        }
        guard let listA = playback.createPlaylist(name: "Early A"),
              let listB = playback.createPlaylist(name: "Early B") else {
            Check.expect(false, "early-receipt playlists were not created")
            return
        }
        playback.addToPlaylist(paths: [files[0].path, files[1].path], playlistID: listA)
        playback.addToPlaylist(paths: [files[2].path, files[3].path], playlistID: listB)
        func asset(_ suffix: String) -> AssetRecord? {
            LibraryCatalog.shared.snapshot().assets.first { $0.path.hasSuffix(suffix) }
        }
        guard let assetA = asset("a.mp4"), let assetC = asset("c.mp4") else {
            Check.expect(false, "early-receipt assets were not saved")
            return
        }
        SpaceBinding.factsOverride = [
            SpaceFact(displayUUID: "DISP-A", displayName: "Built-in", spaceUUID: "space-e1", managedID: 51, isCurrent: false, type: 0),
            SpaceFact(displayUUID: "DISP-A", displayName: "Built-in", spaceUUID: "space-e2", managedID: 52, isCurrent: false, type: 0),
        ]
        playback.refreshTopology(restoreMatching: false)
        guard let first = playback.targets.first(where: { $0.spaceUUID == "space-e1" }),
              let second = playback.targets.first(where: { $0.spaceUUID == "space-e2" }) else {
            Check.expect(false, "early-receipt desktops were not recognized")
            return
        }
        let k1 = first.key
        let k2 = second.key
        func installSessions() {
            LibraryCatalog.shared.mutate { file in
                file.history = []
                file.sessions = [
                    TargetSession(
                        targetKey: k1, assetID: assetA.id, assetName: assetA.name, path: assetA.path,
                        listKind: "playlist", playlistID: listA, folderPath: nil, includeSubdirectories: nil,
                        rotationEnabled: false, paused: true, pauseReason: "manual", order: "random",
                        interval: "5", unavailable: false, provenance: "moonleaf", lastRotatedAt: nil
                    ),
                    TargetSession(
                        targetKey: k2, assetID: assetC.id, assetName: assetC.name, path: assetC.path,
                        listKind: "playlist", playlistID: listB, folderPath: nil, includeSubdirectories: nil,
                        rotationEnabled: false, paused: false, pauseReason: nil, order: "random",
                        interval: "5", unavailable: false, provenance: "moonleaf", lastRotatedAt: nil
                    ),
                ]
            }
            playback.reloadForChecks()
        }
        func label(_ target: DesktopTarget) -> String {
            "\(target.displayName) \(String(format: NSLocalizedString("desktop_n", comment: ""), target.spaceIndex))"
        }
        var seen: [String: PlaybackAssignment] = [:]
        playback.assignmentsSink = { file in
            for (key, assignment) in file.targets {
                seen[key] = assignment
            }
        }
        playback.setCommandRefreshForChecks(true)

        installSessions()
        seen = [:]
        playback.pendingByTarget = [:]
        SpaceBinding.stateReader = {
            guard let assignment = seen[k1] else { return nil }
            return PlaybackStateFile(
                updatedAt: Date(),
                targets: [
                    k1: PlaybackTargetState(
                        path: assignment.path, playing: false, paused: assignment.paused, reason: nil, bound: true,
                        requestID: assignment.requestID, requestedAt: assignment.requestedAt
                    ),
                ]
            )
        }
        let success = playback.randomWallpaper(keys: [k1, k2]) { _ in 0 }
        Check.expect(success[k1] == .applied, "a receipt before the next apply is already done, got \(success)")
        Check.expect(success[k2] == .pending, "the later desktop is still waiting, got \(success)")
        Check.expect(playback.history.contains { $0.targetKeys.contains(k1) }, "the early success is recorded")
        let done = String(format: NSLocalizedString("random_done", comment: ""), 1)
        let waitingSecond = String(format: NSLocalizedString("random_waiting", comment: ""), label(second))
        Check.expect(playback.statusMessage == "\(done) \(waitingSecond)", "the finished desktop is not still waiting, got \(playback.statusMessage ?? "nil")")

        installSessions()
        seen = [:]
        playback.pendingByTarget = [:]
        SpaceBinding.stateReader = {
            guard let assignment = seen[k1] else { return nil }
            return PlaybackStateFile(
                updatedAt: Date(),
                targets: [
                    k1: PlaybackTargetState(
                        path: assignment.path, playing: false, paused: true, reason: "space-bind-failed", bound: false,
                        requestID: assignment.requestID, requestedAt: assignment.requestedAt
                    ),
                ]
            )
        }
        let failure = playback.randomWallpaper(keys: [k1, k2]) { _ in 0 }
        Check.expect(failure[k1] == .failed, "an early bind failure is not left waiting, got \(failure)")
        Check.expect(playback.session(for: k1)?.path == assetA.path, "an early bind failure keeps the old wallpaper")
        Check.expect(playback.history.contains { $0.targetKeys.contains(k1) } == false, "an early bind failure is not a success")
        let failed = String(format: NSLocalizedString("random_failed_targets", comment: ""), label(first))
        let waiting = String(format: NSLocalizedString("random_waiting", comment: ""), label(second))
        Check.expect(playback.statusMessage == "\(waiting) \(failed)", "the early failure is named and only the later desktop waits, got \(playback.statusMessage ?? "nil")")
        Check.expect(playback.statusMessage != NSLocalizedString("bind_failed", comment: ""), "an early bind failure does not collapse to the generic note")
    }

    static func testDeferredStillPaintRevalidatesSpaceAndFailures(_ playback: PlaybackCoordinator) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("moonleaf-still-async-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let first = dir.appendingPathComponent("first.jpg")
        let second = dir.appendingPathComponent("second.jpg")
        let third = dir.appendingPathComponent("third.jpg")
        for url in [first, second, third] {
            try? Data([0xFF, 0xD8, 0xFF]).write(to: url)
        }
        defer {
            SpaceBinding.factsOverride = nil
            SpaceWallpapers.spacesOverride = nil
            SpaceWallpapers.assignOverride = nil
            SpaceWallpapers.paintDesktopOverride = nil
            SpaceWallpapers.targetAssignmentsOverride = nil
            playback.pendingByTarget = [:]
            try? FileManager.default.removeItem(at: dir)
        }

        func pump(timeout: TimeInterval = 5.0, until predicate: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while !predicate(), Date() < deadline {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
            return predicate()
        }

        let display = "DISPLAY-STILL"
        let spaceA = "space-a"
        let spaceB = "space-b"
        let keyA = "d:\(display)|s:\(spaceA)"
        SpaceBinding.factsOverride = [
            SpaceFact(displayUUID: display, displayName: "Built-in", spaceUUID: spaceA, managedID: 41, isCurrent: true, type: 0),
            SpaceFact(displayUUID: display, displayName: "Built-in", spaceUUID: spaceB, managedID: 42, isCurrent: false, type: 0),
        ]
        SpaceWallpapers.spacesOverride = [
            SpaceWallpapers.Space(displayUUID: display, uuid: spaceA, isCurrent: true),
            SpaceWallpapers.Space(displayUUID: display, uuid: spaceB, isCurrent: false),
        ]
        SpaceWallpapers.targetAssignmentsOverride = { _ in [:] }
        var assignedSnapshots: [[SpaceWallpapers.Space: String]] = []
        SpaceWallpapers.assignOverride = { map in
            assignedSnapshots.append(map)
            return true
        }
        SpaceBinding.stateReader = nil
        playback.setCommandRefreshForChecks(false)
        playback.assignmentsSink = nil
        playback.pendingByTarget = [:]
        LibraryCatalog.shared.mutate { file in
            file.sessions = []
            file.history = []
            file.suppressedRestoreKeys = []
        }
        playback.reloadForChecks()
        playback.refreshTopology(restoreMatching: false)
        // 1) Deferred completion: must stay pending with 0 history until paint completes.
        let gate = DispatchSemaphore(value: 0)
        let started = DispatchSemaphore(value: 0)
        var paintedCalls: [(String, String)] = []
        let callLock = NSLock()
        SpaceWallpapers.paintDesktopOverride = { url, _, spaceUUID in
            started.signal()
            _ = gate.wait(timeout: .now() + 5)
            callLock.lock()
            paintedCalls.append((url.lastPathComponent, spaceUUID))
            callLock.unlock()
        }

        let initialOk = playback.apply(
            path: first.path, name: "first", scope: .explicit, displayUUID: display,
            explicitKeys: [keyA], stopRotation: true, origin: "manual",
            confirmedCrossDisplay: true, recordHistory: true
        )
        Check.expect(!initialOk, "visible still apply waits for off-main paint before reporting committed")
        Check.expect(playback.applyPending, "applyPending is true while still paint is in flight")
        Check.expect(playback.session(for: keyA) == nil, "session is not committed before paint finishes")
        Check.expect(playback.history.isEmpty, "history is not recorded before paint finishes")

        _ = started.wait(timeout: .now() + 3)
        gate.signal()
        Check.expect(pump { !playback.applyPending }, "pending still apply settles on main")
        Check.expect(playback.session(for: keyA)?.path == first.path, "session commits after paint succeeds")
        Check.expect(playback.history.count == 1, "history records once after paint succeeds")
        Check.expect(paintedCalls.count == 1 && paintedCalls[0] == ("first.jpg", spaceA), "paint executed on Space A")

        // 2) Space switch A -> B while queued: Space A job must skip native paint so B is untouched.
        paintedCalls = []
        let gate2 = DispatchSemaphore(value: 0)
        let started2 = DispatchSemaphore(value: 0)
        var paintCallCount2 = 0
        SpaceWallpapers.paintDesktopOverride = { url, _, _ in
            paintCallCount2 += 1
            let liveAtEntry = SpaceWallpapers.liveSpaces().first { $0.isCurrent }?.uuid ?? "none"
            callLock.lock()
            paintedCalls.append((url.lastPathComponent, liveAtEntry))
            callLock.unlock()
            if paintCallCount2 == 1 {
                started2.signal()
                _ = gate2.wait(timeout: .now() + 5)
            }
        }
        let keyB = "d:\(display)|s:\(spaceB)"
        _ = playback.apply(
            path: first.path, name: "first", scope: .explicit, displayUUID: display,
            explicitKeys: [keyA], stopRotation: true, origin: "manual",
            confirmedCrossDisplay: true, recordHistory: false
        )
        _ = started2.wait(timeout: .now() + 3)
        _ = playback.apply(
            path: second.path, name: "second", scope: .explicit, displayUUID: display,
            explicitKeys: [keyA], stopRotation: true, origin: "manual",
            confirmedCrossDisplay: true, recordHistory: true
        )
        SpaceWallpapers.spacesOverride = [
            SpaceWallpapers.Space(displayUUID: display, uuid: spaceA, isCurrent: false),
            SpaceWallpapers.Space(displayUUID: display, uuid: spaceB, isCurrent: true),
        ]
        SpaceBinding.factsOverride = [
            SpaceFact(displayUUID: display, displayName: "Built-in", spaceUUID: spaceA, managedID: 41, isCurrent: false, type: 0),
            SpaceFact(displayUUID: display, displayName: "Built-in", spaceUUID: spaceB, managedID: 42, isCurrent: true, type: 0),
        ]
        gate2.signal()
        Check.expect(pump { !playback.applyPending }, "queued job settles after Space switch")
        Check.expect(paintedCalls.count == 1 && paintedCalls[0] == ("first.jpg", spaceA), "deferred paint must never touch newly active Space B, got \(paintedCalls)")
        Check.expect(playback.session(for: keyA)?.path == second.path, "Space A session still updates via Index.plist")
        Check.expect(playback.session(for: keyB) == nil, "Space B remains untouched")

        // 3) Native paint error: must reject session/history, roll back Index.plist, and report failure.
        SpaceWallpapers.spacesOverride = [
            SpaceWallpapers.Space(displayUUID: display, uuid: spaceA, isCurrent: true),
            SpaceWallpapers.Space(displayUUID: display, uuid: spaceB, isCurrent: false),
        ]
        SpaceBinding.factsOverride = [
            SpaceFact(displayUUID: display, displayName: "Built-in", spaceUUID: spaceA, managedID: 41, isCurrent: true, type: 0),
            SpaceFact(displayUUID: display, displayName: "Built-in", spaceUUID: spaceB, managedID: 42, isCurrent: false, type: 0),
        ]
        assignedSnapshots = []
        let historyBeforeFail = playback.history.count
        SpaceWallpapers.paintDesktopOverride = { _, _, _ in
            throw NSError(domain: "TestPaint", code: 42, userInfo: [NSLocalizedDescriptionKey: "boom"])
        }
        let failOk = playback.apply(
            path: third.path, name: "third", scope: .explicit, displayUUID: display,
            explicitKeys: [keyA], stopRotation: true, origin: "manual",
            confirmedCrossDisplay: true, recordHistory: true
        )
        Check.expect(!failOk, "throwing native paint does not return synchronous success")
        Check.expect(pump { !playback.applyPending }, "failed still apply settles on main")
        Check.expect(playback.session(for: keyA)?.path == second.path, "failed paint keeps previous committed session")
        Check.expect(playback.history.count == historyBeforeFail, "failed paint must not record history")
        Check.expect(playback.statusMessage == NSLocalizedString("bind_failed", comment: ""), "failed paint reports bind_failed")
        Check.expect(playback.statusTone == .warning, "failed paint sets warning tone")
        Check.expect(assignedSnapshots.last?.values.contains(second.path) == true, "failed paint rolls back Index.plist to previous wallpaper")

        // 4) randomWallpaper on visible current Space stays pending with 0 history until native paint finishes/fails.
        guard let randList = playback.createPlaylist(name: "StillRand") else {
            Check.expect(false, "failed to create StillRand playlist")
            return
        }
        playback.addToPlaylist(paths: [second.path, third.path], playlistID: randList)
        let assetSecond = LibraryCatalog.shared.asset(path: second.path)!
        LibraryCatalog.shared.mutate { file in
            file.history = []
            file.sessions = [
                TargetSession(
                    targetKey: keyA, assetID: assetSecond.id, assetName: assetSecond.name, path: second.path,
                    listKind: "playlist", playlistID: randList, folderPath: nil, includeSubdirectories: nil,
                    rotationEnabled: false, paused: false, pauseReason: nil, order: "sequential",
                    interval: "5", unavailable: false, provenance: "moonleaf", lastRotatedAt: nil
                )
            ]
        }
        playback.reloadForChecks()
        let gateRand = DispatchSemaphore(value: 0)
        let startedRand = DispatchSemaphore(value: 0)
        SpaceWallpapers.paintDesktopOverride = { _, _, _ in
            startedRand.signal()
            _ = gateRand.wait(timeout: .now() + 5)
            throw NSError(domain: "TestPaint", code: 99, userInfo: nil)
        }
        let randOutcome = playback.randomWallpaper(keys: [keyA]) { _ in 0 }
        Check.expect(randOutcome[keyA] == .pending, "randomWallpaper marks visible still paint pending before completion")
        Check.expect(playback.statusTone == .info, "randomWallpaper shows info tone while still paint is waiting")
        Check.expect(playback.history.isEmpty, "randomWallpaper records no success before paint settles")
        _ = startedRand.wait(timeout: .now() + 3)
        gateRand.signal()
        Check.expect(pump { !playback.applyPending }, "randomWallpaper failed still settles")
        Check.expect(playback.history.isEmpty, "failed randomWallpaper still records no history")
        Check.expect(playback.session(for: keyA)?.path == second.path, "failed randomWallpaper still keeps previous wallpaper")
        Check.expect(playback.statusTone == .warning, "failed randomWallpaper still reports warning tone")
        let targetA = playback.targets.first { $0.key == keyA }!
        let expectedFailedMsg = String(
            format: NSLocalizedString("random_failed_targets", comment: ""),
            "\(targetA.displayName) \(String(format: NSLocalizedString("desktop_n", comment: ""), targetA.spaceIndex))"
        )
        Check.expect(playback.statusMessage == expectedFailedMsg, "failed randomWallpaper names failed target, got \(playback.statusMessage ?? "nil")")
    }
}
