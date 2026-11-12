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
            try? FileManager.default.removeItem(at: root)
        }

        testPlaylistAdd(playback)
        testTargetRefresh(playback)
        testOverlayCommit(playback)
        testListSchedule(playback)
        testConcurrentDueTargets(playback)
        testClearDropsLateReceipt(playback)
        testNewApplySupersedesReceipt(playback)

        if Check.failed == 0 {
            print("playback behavior checks passed")
        } else {
            fputs("\(Check.failed) checks failed\n", stderr)
            exit(1)
        }
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
}
