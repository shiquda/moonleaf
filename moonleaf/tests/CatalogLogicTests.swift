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

func testHistoryCapAndAtomicEvent() {
    var events: [HistoryEvent] = []
    let asset = UUID()
    for index in 0..<1001 {
        let event = HistoryEvent(
            id: UUID(),
            assetID: index == 1000 ? asset : UUID(),
            assetName: "n\(index)",
            appliedAt: Date(timeIntervalSince1970: TimeInterval(index)),
            targetKeys: index == 500 ? ["d:a|s:1", "d:a|s:2"] : ["d:a|s:1"],
            origin: "automatic",
            playlistID: nil,
            playlistName: nil
        )
        events = HistoryLogic.appending(events, event: event, enabled: true, isRestore: false)
    }
    Check.expect(events.count == 1000, "cap keeps 1000 events, got \(events.count)")
    Check.expect(events.first?.assetName == "n1", "oldest event dropped, first is \(events.first?.assetName ?? "nil")")
    Check.expect(events.contains(where: { $0.targetKeys.count == 2 }), "multi-target apply stays one event")
    Check.expect(events.last?.assetID == asset, "newest event kept")

    let blocked = HistoryLogic.appending(events, event: events[0], enabled: false, isRestore: false)
    Check.expect(blocked.count == events.count, "disabled history does not append")
    let restored = HistoryLogic.appending(events, event: events[0], enabled: true, isRestore: true)
    Check.expect(restored.count == events.count, "restore does not append")

    let deduped = HistoryLogic.deduped(events)
    Check.expect(deduped.count == 1000, "these events are unique assets except the cap already dropped one")
    let repeated = HistoryLogic.deduped([
        HistoryEvent(id: UUID(), assetID: asset, assetName: "old", appliedAt: Date(timeIntervalSince1970: 1), targetKeys: ["a"], origin: "manual", playlistID: nil, playlistName: nil),
        HistoryEvent(id: UUID(), assetID: asset, assetName: "new", appliedAt: Date(timeIntervalSince1970: 2), targetKeys: ["b", "c"], origin: "manual", playlistID: nil, playlistName: nil),
    ])
    Check.expect(repeated.count == 1 && repeated[0].assetName == "new" && repeated[0].targetKeys == ["b", "c"], "dedupe keeps latest targets")
}

func testPlaylistRules() {
    let a = UUID(), b = UUID(), c = UUID()
    let added = PlaylistLogic.adding([b, a, c, b], to: [a])
    Check.expect(added == [a, b, c], "same list does not repeat an asset")
    let moved = PlaylistLogic.moving([a, b, c], from: 0, to: 2)
    Check.expect(moved == [b, c, a], "drag reorder")
    let playable = PlaylistLogic.playable([a, b, c]) { $0 != b }
    Check.expect(playable.ids == [a, c] && playable.skipped == 1, "unavailable skipped and counted")
    let next = PlaylistLogic.nextID(playable: [a, c], current: a, order: "sequential", randomIndex: { _ in 0 })
    Check.expect(next == c, "sequential next")
    let random = PlaylistLogic.nextID(playable: [a, c], current: a, order: "random", randomIndex: { _ in 0 })
    Check.expect(random == c, "random avoids current when another exists")
    Check.expect(PlaylistLogic.nextID(playable: [], current: nil, order: "sequential", randomIndex: { _ in 0 }) == nil, "empty list has no next")
}

func testTargetsAndScope() {
    let spaces = [
        SpaceFact(displayUUID: "D1", displayName: "Built-in", spaceUUID: "S1", managedID: 1, isCurrent: true, type: 0),
        SpaceFact(displayUUID: "D1", displayName: "Built-in", spaceUUID: "S2", managedID: 2, isCurrent: false, type: 0),
        SpaceFact(displayUUID: "D1", displayName: "Built-in", spaceUUID: "FS", managedID: 9, isCurrent: false, type: 4),
        SpaceFact(displayUUID: "D2", displayName: "External", spaceUUID: "S3", managedID: 3, isCurrent: true, type: 0),
    ]
    let separate = TargetLogic.targets(spaces: spaces, separateSpaces: true)
    Check.expect(separate.count == 3, "fullscreen space is not a wallpaper target, got \(separate.count)")
    Check.expect(separate[0].key == "d:D1|s:S1" && separate[0].spaceIndex == 1, "stable display+space key")
    Check.expect(separate[1].key == "d:D1|s:S2" && separate[1].spaceIndex == 2, "second desktop on same display")
    Check.expect(!separate.contains(where: { $0.spaceUUID == "FS" }), "no invented fullscreen target")

    let current = ScopeLogic.resolve(kind: .currentDesktop, targets: separate, displayUUID: "D1", explicitKeys: [], allowCrossDisplay: false)
    Check.expect(current == .success([separate[0]]), "current desktop stays on the chosen display")
    let allOnDisplay = ScopeLogic.resolve(kind: .displayDesktops, targets: separate, displayUUID: "D1", explicitKeys: [], allowCrossDisplay: false)
    Check.expect(allOnDisplay == .success([separate[0], separate[1]]), "display scope does not include the other display")
    let cross = ScopeLogic.resolve(kind: .explicit, targets: separate, displayUUID: "D1", explicitKeys: [separate[0].key, separate[2].key], allowCrossDisplay: false)
    Check.expect(cross == .failure(.crossDisplayNeedsConfirmation), "cross-display batch is not silent")
    let confirmed = ScopeLogic.resolve(kind: .explicit, targets: separate, displayUUID: "D1", explicitKeys: [separate[0].key, separate[2].key], allowCrossDisplay: true)
    Check.expect(confirmed == .success([separate[0], separate[2]]), "confirmed cross-display is explicit")

    let sharedSpaces = [
        SpaceFact(displayUUID: "D1", displayName: "Built-in", spaceUUID: "S1", managedID: 1, isCurrent: true, type: 0),
        SpaceFact(displayUUID: "D2", displayName: "External", spaceUUID: "S1", managedID: 1, isCurrent: true, type: 0),
        SpaceFact(displayUUID: "D1", displayName: "Built-in", spaceUUID: "S2", managedID: 2, isCurrent: false, type: 0),
        SpaceFact(displayUUID: "D2", displayName: "External", spaceUUID: "S2", managedID: 2, isCurrent: false, type: 0),
    ]
    let shared = TargetLogic.targets(spaces: sharedSpaces, separateSpaces: false)
    Check.expect(shared.count == 2, "shared spaces are not a cartesian product, got \(shared.count)")
    Check.expect(shared[0].displayUUIDs == ["D1", "D2"] && shared[0].key == "span:S1", "one target covers every display of that space")
    let sharedAll = ScopeLogic.resolve(kind: .displayDesktops, targets: shared, displayUUID: "D1", explicitKeys: [], allowCrossDisplay: false)
    Check.expect(sharedAll == .success(shared), "shared-space desktops are the real scope")
}

func testStorage() {
    let summary = StorageLogic.summarize([
        FileFact(path: "/lib/a.jpg", isSymlink: false, byteSize: 10, insideLibrary: true),
        FileFact(path: "/lib/link.mp4", isSymlink: true, byteSize: 999, insideLibrary: true),
        FileFact(path: "/outside/b.png", isSymlink: false, byteSize: 50, insideLibrary: false),
    ])
    Check.expect(summary.libraryBytes == 10 && summary.libraryKnown, "symlink is not exclusive usage")
    Check.expect(summary.externalPaths == ["/lib/link.mp4", "/outside/b.png"], "external refs listed")
    let unknown = StorageLogic.summarize([
        FileFact(path: "/lib/a.jpg", isSymlink: false, byteSize: nil, insideLibrary: true),
    ])
    Check.expect(unknown.libraryBytes == nil && !unknown.libraryKnown, "unknown size is not reported as zero")
}

func testCommitPaintAndSchedule() {
    let when = Date(timeIntervalSince1970: 1_700_000_000)
    Check.expect(!VisiblePaint.allowed(targetSpaceUUID: "old", liveCurrentSpaceUUIDs: ["new"]), "stale space must not paint the visible screen")
    Check.expect(VisiblePaint.allowed(targetSpaceUUID: "new", liveCurrentSpaceUUIDs: ["new"]), "live current space may be painted")

    Check.expect(!ApplyCommit.overlaySucceeded(
        requestID: "new-request", path: "/new.mp4", requestedAt: when,
        reportedRequestID: "old-request", reportedPath: "/new.mp4", reportedAt: when,
        bound: true, reason: nil
    ), "old request cannot impersonate a new apply")
    Check.expect(!ApplyCommit.overlaySucceeded(
        requestID: "req", path: "/new.mp4", requestedAt: when,
        reportedRequestID: "req", reportedPath: "/old.mp4", reportedAt: when,
        bound: true, reason: nil
    ), "matching request with the old path is not success")
    Check.expect(!ApplyCommit.overlaySucceeded(
        requestID: "req", path: "/new.mp4", requestedAt: when,
        reportedRequestID: "req", reportedPath: "/new.mp4", reportedAt: when.addingTimeInterval(-30),
        bound: true, reason: nil
    ), "stale timestamp is not success")
    Check.expect(ApplyCommit.overlayFailed(
        requestID: "req", path: "/new.mp4", requestedAt: when,
        reportedRequestID: "req", reportedPath: "/new.mp4", reportedAt: when,
        bound: false, reason: "space-bind-failed"
    ), "matching bind failure is a failure")
    Check.expect(ApplyCommit.overlaySucceeded(
        requestID: "req", path: "/new.mp4", requestedAt: when,
        reportedRequestID: "req", reportedPath: "/new.mp4", reportedAt: when,
        bound: true, reason: "not-visible"
    ), "a bound hidden desktop is a successful apply")

    let now = Date(timeIntervalSince1970: 10_000)
    Check.expect(RotationSchedule.isDue(
        listKind: "playlist", rotationEnabled: true, paused: false, unavailable: false,
        intervalRaw: "1", lastRotatedAt: now.addingTimeInterval(-61), now: now, libraryShuffleEnabled: false
    ), "named list rotates on its own interval while library shuffle is off")
    Check.expect(!RotationSchedule.isDue(
        listKind: "playlist", rotationEnabled: true, paused: false, unavailable: false,
        intervalRaw: "5", lastRotatedAt: now.addingTimeInterval(-61), now: now, libraryShuffleEnabled: true
    ), "a longer list interval is not the global one-minute tick")
    Check.expect(!RotationSchedule.isDue(
        listKind: "library", rotationEnabled: true, paused: false, unavailable: false,
        intervalRaw: "1", lastRotatedAt: now.addingTimeInterval(-61), now: now, libraryShuffleEnabled: false
    ), "library pool stays off when library shuffle is off")
}

func testRandomChoice() {
    let current = UUID()
    let other = UUID()
    Check.expect(RandomLogic.choose(candidates: [], current: nil, randomIndex: { _ in 0 }) == .noSource, "empty source is not a change")
    Check.expect(RandomLogic.choose(candidates: [current], current: current, randomIndex: { _ in 0 }) == .noOther, "the only current asset is not a change")
    Check.expect(RandomLogic.choose(candidates: [current, other], current: current, randomIndex: { _ in 0 }) == .pick(other), "random skips the current asset")
    Check.expect(RandomLogic.source(listKind: "playlist", playlistID: nil, folderPath: nil, includeSubdirectories: nil) == .missing, "a playlist without an id is not a source")
    Check.expect(RandomLogic.source(listKind: nil, playlistID: nil, folderPath: nil, includeSubdirectories: nil) == .library, "no list uses the library")
    let list = UUID()
    Check.expect(RandomLogic.source(listKind: "playlist", playlistID: list, folderPath: nil, includeSubdirectories: nil) == .playlist(list), "an active playlist stays the source")
}


@main
struct CatalogChecks {
    static func main() {
        testHistoryCapAndAtomicEvent()
        testPlaylistRules()
        testTargetsAndScope()
        testStorage()
        testCommitPaintAndSchedule()
        testRandomChoice()
        if Check.failed == 0 {
            print("catalog logic checks passed")
        } else {
            fputs("\(Check.failed) checks failed\n", stderr)
            exit(1)
        }
    }
}
