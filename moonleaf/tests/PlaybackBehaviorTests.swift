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
            try? FileManager.default.removeItem(at: root)
        }

        testPlaylistAdd(playback)
        testTargetRefresh(playback)
        testOverlayCommit(playback)
        testListSchedule(playback)

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
        playback.pending = pendingRequest()
        playback.acceptReported(PlaybackStateFile(
            updatedAt: when,
            targets: [key: PlaybackTargetState(
                path: "/new.mp4", playing: true, paused: false, reason: nil, bound: true,
                requestID: "other", requestedAt: when
            )]
        ))
        Check.expect(playback.history.isEmpty, "unrelated state must not record history")
        Check.expect(playback.sessions.first?.path == "/old.jpg", "unrelated state must not switch the session")
        Check.expect(playback.pending != nil, "unrelated state leaves the request open")

        playback.acceptReported(PlaybackStateFile(
            updatedAt: when,
            targets: [key: PlaybackTargetState(
                path: "/new.mp4", playing: false, paused: true, reason: "space-bind-failed", bound: false,
                requestID: request, requestedAt: when
            )]
        ))
        Check.expect(playback.history.isEmpty, "bind failure must not record history")
        Check.expect(playback.sessions.first?.path == "/old.jpg", "bind failure must not switch the list")
        Check.expect(playback.pending == nil, "bind failure closes the request")
        Check.expect(playback.statusMessage == NSLocalizedString("bind_failed", comment: ""), "bind failure is reported")

        playback.pending = pendingRequest()
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
        Check.expect(playback.pending == nil, "success closes the request")
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
}
