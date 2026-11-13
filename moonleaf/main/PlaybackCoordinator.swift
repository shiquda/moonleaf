//
//  PlaybackCoordinator.swift
//  moonleaf
//
//  One owner for what is on each desktop. The menu bar and the window call
//  the same methods. Player state wins over the last request when they differ.
//

import AppKit
import Combine
import Foundation

struct ListStamp {
    var kind: String
    var playlistID: UUID?
    var playlistName: String?
    var order: String
    var interval: String
    var folderPath: String?
    var includeSubdirectories: Bool?
    var rotationEnabled: Bool
}

struct PendingOverlay {
    var requestID: String
    var requestedAt: Date
    var path: String
    var assetID: UUID
    var assetName: String
    var keys: [String]
    var origin: String
    var playlistID: UUID?
    var playlistName: String?
    var recordHistory: Bool
    var stopRotation: Bool
    var stamp: ListStamp?
    var touchRotationClock: Bool
}

@MainActor
final class PlaybackCoordinator: ObservableObject {
    static let shared = PlaybackCoordinator()

    @Published private(set) var separateSpaces = true
    @Published private(set) var targets: [DesktopTarget] = []
    @Published private(set) var sessions: [TargetSession] = []
    @Published private(set) var playlists: [NamedPlaylist] = []
    @Published private(set) var history: [HistoryEvent] = []
    @Published private(set) var historyEnabled = true
    @Published private(set) var playerState: [String: PlaybackTargetState] = [:]
    @Published private(set) var statusMessage: String?
    @Published private(set) var catalogRevision = 0

    private let catalog = LibraryCatalog.shared
    private var stateObserver: NSObjectProtocol?
    private var canTouchApp = false
    static let topologyWatch: [Notification.Name] = [
        NSApplication.didChangeScreenParametersNotification,
        NSWorkspace.didWakeNotification,
        NSWorkspace.activeSpaceDidChangeNotification,
    ]
    var pendingByTarget: [String: PendingOverlay] = [:]
    /// Tests capture the assignment file instead of writing the shared one.
    var assignmentsSink: ((PlaybackAssignmentFile) -> Void)?
    private var rotationTimer: DispatchSourceTimer?

    private init() {
        stateObserver = DistributedNotificationCenter.default().addObserver(
            forName: PlaybackNotices.state,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.readPlayerState() }
        }
    }

    func start() {
        canTouchApp = true
        refreshTopology(restoreMatching: true)
        readPlayerState()
        startRotationTimer()
    }

    func refreshForCommand() {
        refreshTopology(restoreMatching: false)
        acceptReported(SpaceBinding.readState())
    }

    func installTopologyWatch(on target: Any, selector: Selector) {
        for name in Self.topologyWatch {
            let center: NotificationCenter = name == NSApplication.didChangeScreenParametersNotification
                ? .default
                : NSWorkspace.shared.notificationCenter
            center.addObserver(target, selector: selector, name: name, object: nil)
        }
    }

    private func startRotationTimer() {
        guard rotationTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in
            self?.rotateDueSessions()
        }
        timer.resume()
        rotationTimer = timer
    }
    func refreshTopology(restoreMatching: Bool) {
        let live = SpaceBinding.liveTargets()
        separateSpaces = live.separate
        targets = live.targets
        let liveKeys = Set(live.targets.map(\.key))
        seedMissingTargets(targets: live.targets)
        catalog.mutate { file in
            for index in file.sessions.indices {
                file.sessions[index].unavailable = !liveKeys.contains(file.sessions[index].targetKey)
            }
        }
        reloadPublished()
        publishCurrentPath()
        if restoreMatching {
            pushAssignments(recordHistory: false)
        }
    }

    func apply(
        path: String,
        name: String?,
        scope: ScopeKind,
        displayUUID: String?,
        explicitKeys: [String] = [],
        stopRotation: Bool,
        origin: String,
        confirmedCrossDisplay: Bool,
        recordHistory: Bool,
        playlistID: UUID? = nil,
        playlistName: String? = nil,
        stamp: ListStamp? = nil,
        touchRotationClock: Bool = false
    ) -> Bool {
        if canTouchApp {
            refreshForCommand()
        }
        guard FileManager.default.fileExists(atPath: path) else {
            statusMessage = NSLocalizedString("apply_missing_file", comment: "")
            return false
        }
        let kind = MediaKind.from(path: path)
        guard kind != .unknown else {
            statusMessage = NSLocalizedString("apply_unsupported", comment: "")
            return false
        }
        switch ScopeLogic.resolve(
            kind: scope,
            targets: targets,
            displayUUID: displayUUID,
            explicitKeys: explicitKeys,
            allowCrossDisplay: confirmedCrossDisplay
        ) {
        case .failure(let error):
            statusMessage = message(for: error)
            return false
        case .success(let chosen):
            guard !chosen.isEmpty else {
                statusMessage = NSLocalizedString("apply_none", comment: "")
                return false
            }
            let asset = catalog.ensureAsset(
                path: path,
                name: name,
                source: path.hasPrefix(MoonleafConfigStore.libraryRoot.path) ? "library" : "external",
                origin: origin
            )
            if kind.usesSpaceBoundOverlay {
                let request = PendingOverlay(
                    requestID: UUID().uuidString,
                    requestedAt: Date(),
                    path: path,
                    assetID: asset.id,
                    assetName: asset.name,
                    keys: chosen.map(\.key),
                    origin: origin,
                    playlistID: stamp?.playlistID ?? playlistID,
                    playlistName: stamp?.playlistName ?? playlistName,
                    recordHistory: recordHistory,
                    stopRotation: stopRotation,
                    stamp: stamp,
                    touchRotationClock: touchRotationClock
                )
                for key in request.keys {
                    pendingByTarget[key] = request
                }
                statusMessage = nil
                pushAssignments(recordHistory: false)
                return false
            }
            var snapshot = catalog.snapshot()
            var appliedKeys: [String] = []
            for target in chosen {
                guard assignStill(path, target: target) else { continue }
                writeCommittedSession(
                    snapshot: &snapshot,
                    asset: asset,
                    path: path,
                    targetKey: target.key,
                    stopRotation: stopRotation,
                    stamp: stamp
                )
                appliedKeys.append(target.key)
            }
            guard !appliedKeys.isEmpty else {
                statusMessage = NSLocalizedString("apply_none", comment: "")
                return false
            }
            for key in appliedKeys {
                pendingByTarget.removeValue(forKey: key)
            }
            if recordHistory {
                snapshot.history = HistoryLogic.appending(
                    snapshot.history,
                    event: HistoryEvent(
                        id: UUID(),
                        assetID: asset.id,
                        assetName: asset.name,
                        appliedAt: Date(),
                        targetKeys: appliedKeys,
                        origin: origin,
                        playlistID: playlistID,
                        playlistName: playlistName
                    ),
                    enabled: snapshot.historyEnabled,
                    isRestore: false
                )
            }
            catalog.mutate { $0 = snapshot }
            reloadPublished()
            pushAssignments(recordHistory: false)
            publishCurrentPath()
            if canTouchApp,
               let current = currentTarget(displayUUID: SpaceBinding.currentDisplayUUID()),
               appliedKeys.contains(current.key) {
                MoonleafConfigStore.shared.writeCurrentWallpaperAsync(path)
            }
            statusMessage = nil
            return true
        }
    }

    func assignList(playlistID: UUID, targetKey: String) -> Bool {
        guard let target = targets.first(where: { $0.key == targetKey }), !targetUnavailable(targetKey) else {
            statusMessage = NSLocalizedString("scope_unknown_target", comment: "")
            return false
        }
        let snapshot = catalog.snapshot()
        guard let list = snapshot.playlists.first(where: { $0.id == playlistID }) else {
            statusMessage = NSLocalizedString("list_missing", comment: "")
            return false
        }
        let resolved = resolvedPlaylist(list, snapshot: snapshot)
        guard !resolved.isEmpty else {
            statusMessage = list.assetIDs.isEmpty
                ? NSLocalizedString("list_empty", comment: "")
                : NSLocalizedString("list_all_unavailable", comment: "")
            return false
        }
        let existing = snapshot.sessions.first(where: { $0.targetKey == targetKey })
        let first = resolved[0]
        return apply(
            path: first.path,
            name: first.name,
            scope: .explicit,
            displayUUID: target.displayUUIDs.first,
            explicitKeys: [targetKey],
            stopRotation: false,
            origin: "manual",
            confirmedCrossDisplay: true,
            recordHistory: true,
            playlistID: list.id,
            playlistName: list.name,
            stamp: ListStamp(
                kind: "playlist",
                playlistID: list.id,
                playlistName: list.name,
                order: existing?.order ?? list.order,
                interval: existing?.interval ?? list.interval,
                folderPath: nil,
                includeSubdirectories: nil,
                rotationEnabled: true
            )
        )
    }

    func assignPool(kind: String, targetKey: String, folderPath: String? = nil, includeSubdirectories: Bool = false) -> Bool {
        guard let target = targets.first(where: { $0.key == targetKey }) else {
            statusMessage = NSLocalizedString("scope_unknown_target", comment: "")
            return false
        }
        let items = poolItems(kind: kind, playlistID: nil, folderPath: folderPath, includeSubdirectories: includeSubdirectories)
        guard let first = items.first else {
            statusMessage = NSLocalizedString("list_empty", comment: "")
            return false
        }
        let existing = catalog.snapshot().sessions.first(where: { $0.targetKey == targetKey })
        return apply(
            path: first.path,
            name: first.name,
            scope: .explicit,
            displayUUID: target.displayUUIDs.first,
            explicitKeys: [targetKey],
            stopRotation: false,
            origin: "manual",
            confirmedCrossDisplay: true,
            recordHistory: true,
            stamp: ListStamp(
                kind: kind,
                playlistID: nil,
                playlistName: nil,
                order: existing?.order ?? "random",
                interval: existing?.interval ?? UserDefaults.standard.string(forKey: "moonleaf_shuffleInterval") ?? "5",
                folderPath: folderPath,
                includeSubdirectories: includeSubdirectories,
                rotationEnabled: true
            )
        )
    }

    func setPaused(_ paused: Bool, targetKey: String) {
        guard !targetUnavailable(targetKey) else {
            statusMessage = NSLocalizedString("scope_unknown_target", comment: "")
            return
        }
        catalog.mutate { file in
            guard let index = file.sessions.firstIndex(where: { $0.targetKey == targetKey }) else { return }
            file.sessions[index].paused = paused
            file.sessions[index].pauseReason = paused ? "manual" : nil
        }
        reloadPublished()
        pushAssignments(recordHistory: false)
    }
    func clearTarget(_ key: String) {
        pendingByTarget.removeValue(forKey: key)
        catalog.mutate { file in
            file.sessions.removeAll { $0.targetKey == key }
            if !file.suppressedRestoreKeys.contains(key) {
                file.suppressedRestoreKeys.append(key)
            }
        }
        reloadPublished()
        publishCurrentPath()
        pushAssignments(recordHistory: false)
    }

    func clearCurrent() {
        guard let target = currentTarget(displayUUID: SpaceBinding.currentDisplayUUID()) else { return }
        clearTarget(target.key)
    }

    func enableRotationOnCurrentDesktop() {
        guard let target = currentTarget(displayUUID: SpaceBinding.currentDisplayUUID()) else { return }
        if session(for: target.key) != nil {
            catalog.mutate { file in
                guard let index = file.sessions.firstIndex(where: { $0.targetKey == target.key }) else { return }
                file.sessions[index].rotationEnabled = true
                if file.sessions[index].listKind == nil { file.sessions[index].listKind = "library" }
            }
            reloadPublished()
            return
        }
        _ = assignPool(kind: "library", targetKey: target.key)
    }

    func next(targetKey: String) {
        guard let session = sessions.first(where: { $0.targetKey == targetKey }), !session.unavailable else {
            statusMessage = NSLocalizedString("scope_unknown_target", comment: "")
            return
        }
        advance(session, origin: "manual")
    }

    func rotateDueSessions(now: Date = Date()) {
        let libraryShuffle = UserDefaults.standard.bool(forKey: "moonleaf_shuffleEnabled")
        let held = Set(pendingByTarget.keys)
        for session in catalog.snapshot().sessions where !held.contains(session.targetKey) && RotationSchedule.isDue(
            listKind: session.listKind,
            rotationEnabled: session.rotationEnabled,
            paused: session.paused,
            unavailable: session.unavailable,
            intervalRaw: session.interval,
            lastRotatedAt: session.lastRotatedAt,
            now: now,
            libraryShuffleEnabled: libraryShuffle
        ) {
            advance(session, origin: "automatic")
        }
    }

    func setLibraryShuffleInterval(_ raw: String) {
        catalog.mutate { file in
            for index in file.sessions.indices {
                let kind = file.sessions[index].listKind
                if kind == nil || kind == "library" {
                    file.sessions[index].interval = raw
                }
            }
        }
        reloadPublished()
    }

    func createPlaylist(name: String) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let id = UUID()
        catalog.mutate { file in
            file.playlists.append(NamedPlaylist(id: id, name: trimmed, assetIDs: [], order: "sequential", interval: "5"))
        }
        reloadPublished()
        return id
    }

    func renamePlaylist(_ id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        catalog.mutate { file in
            guard let index = file.playlists.firstIndex(where: { $0.id == id }) else { return }
            file.playlists[index].name = trimmed
        }
        reloadPublished()
    }

    func deletePlaylist(_ id: UUID) {
        catalog.mutate { file in
            file.playlists.removeAll { $0.id == id }
            for index in file.sessions.indices where file.sessions[index].playlistID == id {
                file.sessions[index].playlistID = nil
                file.sessions[index].listKind = nil
                file.sessions[index].rotationEnabled = false
            }
        }
        reloadPublished()
        pushAssignments(recordHistory: false)
    }

    func addToPlaylist(paths: [String], playlistID: UUID) {
        catalog.addAssets(paths.map { (path: $0, name: nil) }, to: playlistID)
        reloadPublished()
    }

    func removeFromPlaylist(assetID: UUID, playlistID: UUID) {
        catalog.mutate { file in
            guard let index = file.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
            file.playlists[index].assetIDs = PlaylistLogic.removing(assetID, from: file.playlists[index].assetIDs)
        }
        reloadPublished()
    }

    func moveInPlaylist(playlistID: UUID, from: Int, to: Int) {
        catalog.mutate { file in
            guard let index = file.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
            file.playlists[index].assetIDs = PlaylistLogic.moving(file.playlists[index].assetIDs, from: from, to: to)
        }
        reloadPublished()
    }

    func updatePlaylistSettings(_ id: UUID, order: String, interval: String) {
        catalog.mutate { file in
            guard let index = file.playlists.firstIndex(where: { $0.id == id }) else { return }
            file.playlists[index].order = order
            file.playlists[index].interval = interval
            for sessionIndex in file.sessions.indices where file.sessions[sessionIndex].playlistID == id {
                file.sessions[sessionIndex].order = order
                file.sessions[sessionIndex].interval = interval
            }
        }
        reloadPublished()
    }

    func setHistoryEnabled(_ enabled: Bool) {
        catalog.mutate { $0.historyEnabled = enabled }
        reloadPublished()
    }

    func removeHistory(_ id: UUID) {
        catalog.mutate { $0.history.removeAll { $0.id == id } }
        reloadPublished()
    }

    func clearHistory() {
        catalog.mutate { $0.history.removeAll() }
        reloadPublished()
    }

    func setFutureSaveDirectory(_ path: String?) {
        catalog.mutate { $0.futureSaveDirectory = path }
        reloadPublished()
    }

    func futureSaveDirectory() -> String? {
        catalog.snapshot().futureSaveDirectory
    }

    func saveDirectory() -> URL {
        if let path = futureSaveDirectory(), FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return MoonleafConfigStore.libraryRoot
    }

    func targetUnavailable(_ key: String) -> Bool {
        if let session = sessions.first(where: { $0.targetKey == key }), session.unavailable { return true }
        return !targets.contains(where: { $0.key == key })
    }

    func currentTarget(displayUUID: String?) -> DesktopTarget? {
        let current = targets.filter(\.isCurrent)
        if let displayUUID {
            return current.first { $0.displayUUIDs.contains(displayUUID) } ?? current.first
        }
        return current.first
    }

    func session(for key: String) -> TargetSession? {
        sessions.first { $0.targetKey == key }
    }

    func playbackDescription(for key: String) -> String {
        if targetUnavailable(key) {
            return NSLocalizedString("target_unavailable", comment: "")
        }
        if let state = playerState[key] {
            if !state.bound && state.reason == "space-bind-failed" {
                return NSLocalizedString("bind_failed", comment: "")
            }
            if state.paused {
                return pauseText(state.reason ?? "paused")
            }
            if state.playing {
                return NSLocalizedString("playback_playing", comment: "")
            }
        }
        if let session = session(for: key) {
            if session.provenance == "unknown" {
                return NSLocalizedString("playback_unknown", comment: "")
            }
            if session.paused {
                return pauseText(session.pauseReason ?? "manual")
            }
            if let path = session.path, MediaKind.from(path: path).usesSpaceBoundOverlay, playerState[key] == nil {
                return NSLocalizedString("playback_unknown", comment: "")
            }
            return NSLocalizedString("playback_showing", comment: "")
        }
        return NSLocalizedString("playback_unknown", comment: "")
    }

    func assetRecord(path: String) -> AssetRecord? {
        catalog.asset(path: path) ?? {
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return catalog.ensureAsset(path: path, name: nil, source: path.hasPrefix(MoonleafConfigStore.libraryRoot.path) ? "library" : "external", origin: nil)
        }()
    }

    func resolvedPath(assetID: UUID) -> String? {
        catalog.resolvedAsset(assetID)?.url.path
    }

    func membershipNames(path: String) -> [String] {
        guard let asset = catalog.asset(path: path) else { return [] }
        return catalog.playlists(containing: asset.id).map(\.name)
    }

    func historyForDisplay() -> [HistoryEvent] {
        history.reversed()
    }

    private func advance(_ session: TargetSession, origin: String) {
        let items = poolItems(
            kind: session.listKind ?? "library",
            playlistID: session.playlistID,
            folderPath: session.folderPath,
            includeSubdirectories: session.includeSubdirectories ?? false
        )
        let ids = items.map(\.id)
        guard let nextID = PlaylistLogic.nextID(
            playable: ids,
            current: session.assetID,
            order: session.order,
            randomIndex: { count in Int.random(in: 0..<count) }
        ), let next = items.first(where: { $0.id == nextID }) else {
            statusMessage = NSLocalizedString("list_empty", comment: "")
            return
        }
        let target = targets.first { $0.key == session.targetKey }
        let ok = apply(
            path: next.path,
            name: next.name,
            scope: .explicit,
            displayUUID: target?.displayUUIDs.first,
            explicitKeys: [session.targetKey],
            stopRotation: false,
            origin: origin,
            confirmedCrossDisplay: true,
            recordHistory: true,
            playlistID: session.playlistID,
            playlistName: playlists.first { $0.id == session.playlistID }?.name,
            touchRotationClock: true
        )
        guard ok else { return }
        catalog.mutate { file in
            guard let index = file.sessions.firstIndex(where: { $0.targetKey == session.targetKey }) else { return }
            file.sessions[index].lastRotatedAt = Date()
            file.sessions[index].listKind = session.listKind
            file.sessions[index].playlistID = session.playlistID
            file.sessions[index].rotationEnabled = session.rotationEnabled
            file.sessions[index].order = session.order
            file.sessions[index].interval = session.interval
        }
        reloadPublished()
    }

    private struct PoolItem {
        var id: UUID
        var path: String
        var name: String
    }

    private func poolItems(kind: String, playlistID: UUID?, folderPath: String?, includeSubdirectories: Bool) -> [PoolItem] {
        let snapshot = catalog.snapshot()
        switch kind {
        case "playlist":
            guard let list = snapshot.playlists.first(where: { $0.id == playlistID }) else { return [] }
            return resolvedPlaylist(list, snapshot: snapshot).map { PoolItem(id: $0.id, path: $0.path, name: $0.name) }
        case "favorites":
            return snapshot.favoriteIDs.compactMap { id in
                guard let resolved = catalog.resolvedAsset(id) else { return nil }
                return PoolItem(id: id, path: resolved.url.path, name: resolved.record.name)
            }
        case "folder":
            guard let folderPath else { return [] }
            return mediaFiles(in: folderPath, recursive: includeSubdirectories).compactMap { path in
                let record = catalog.ensureAsset(path: path, name: nil, source: "external", origin: nil)
                return PoolItem(id: record.id, path: path, name: record.name)
            }
        default:
            return mediaFiles(in: MoonleafConfigStore.libraryRoot.path, recursive: false).compactMap { path in
                let record = catalog.ensureAsset(path: path, name: nil, source: "library", origin: nil)
                return PoolItem(id: record.id, path: path, name: record.name)
            }
        }
    }

    private func resolvedPlaylist(_ list: NamedPlaylist, snapshot: CatalogFile) -> [(id: UUID, path: String, name: String)] {
        list.assetIDs.compactMap { id in
            guard let resolved = catalog.resolvedAsset(id) else { return nil }
            return (id, resolved.url.path, resolved.record.name)
        }
    }

    private func writeCommittedSession(
        snapshot: inout CatalogFile,
        asset: AssetRecord,
        path: String,
        targetKey: String,
        stopRotation: Bool,
        stamp: ListStamp?
    ) {
        var session = snapshot.sessions.first(where: { $0.targetKey == targetKey }) ?? TargetSession(
            targetKey: targetKey,
            assetID: asset.id,
            assetName: asset.name,
            path: path,
            listKind: nil,
            playlistID: nil,
            folderPath: nil,
            includeSubdirectories: nil,
            rotationEnabled: false,
            paused: false,
            pauseReason: nil,
            order: "random",
            interval: UserDefaults.standard.string(forKey: "moonleaf_shuffleInterval") ?? "5",
            unavailable: false,
            provenance: "moonleaf",
            lastRotatedAt: nil
        )
        session.assetID = asset.id
        session.assetName = asset.name
        session.path = path
        session.unavailable = false
        session.provenance = "moonleaf"
        session.paused = false
        session.pauseReason = nil
        if stopRotation {
            session.rotationEnabled = false
            session.listKind = nil
            session.playlistID = nil
        } else if let stamp {
            session.listKind = stamp.kind
            session.playlistID = stamp.playlistID
            session.folderPath = stamp.folderPath
            session.includeSubdirectories = stamp.includeSubdirectories
            session.rotationEnabled = stamp.rotationEnabled
            session.order = stamp.order
            session.interval = stamp.interval
        }
        snapshot.suppressedRestoreKeys.removeAll { $0 == targetKey }
        if let index = snapshot.sessions.firstIndex(where: { $0.targetKey == targetKey }) {
            snapshot.sessions[index] = session
        } else {
            snapshot.sessions.append(session)
        }
    }

    private func assignStill(_ path: String, target: DesktopTarget) -> Bool {
        let url = URL(fileURLWithPath: path)
        let spaces = SpaceWallpapers.liveSpaces().filter { space in
            space.uuid == target.spaceUUID && target.displayUUIDs.contains(space.displayUUID)
        }
        guard !spaces.isEmpty else { return false }
        var assigned: [SpaceWallpapers.Space: String] = [:]
        for space in spaces { assigned[space] = path }
        guard SpaceWallpapers.assign(assigned) else { return false }
        if spaces.contains(where: { !$0.isCurrent }) {
            SpaceWallpapers.reload()
        }
        let liveCurrent = Set(spaces.filter(\.isCurrent).map(\.uuid))
        guard VisiblePaint.allowed(targetSpaceUUID: target.spaceUUID, liveCurrentSpaceUUIDs: liveCurrent) else {
            return true
        }
        for space in spaces where space.isCurrent {
            guard let screen = SpaceBinding.screen(for: space.displayUUID) else { return false }
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            } catch {
                return false
            }
        }
        return true
    }

    private func seedMissingTargets(targets: [DesktopTarget]) {
        let snapshot = catalog.snapshot()
        let existingKeys = Set(snapshot.sessions.map(\.targetKey))
        let suppressed = Set(snapshot.suppressedRestoreKeys)
        let candidates = targets.filter { !existingKeys.contains($0.key) && !suppressed.contains($0.key) }
        guard !candidates.isEmpty else { return }

        let inTestOverride = SpaceWallpapers.targetAssignmentsOverride != nil
            || SpaceWallpapers.spacesOverride != nil
            || SpaceWallpapers.assignOverride != nil
        var legacyPaths = Set<String>()
        if !inTestOverride {
            if let currentPath = MoonleafConfigStore.shared.readCurrentWallpaper(), !currentPath.isEmpty {
                legacyPaths.insert(URL(fileURLWithPath: currentPath).standardizedFileURL.path)
                legacyPaths.insert(URL(fileURLWithPath: currentPath).resolvingSymlinksInPath().path)
            }
            for path in MoonleafConfigStore.shared.readScreenWallpapers().values where !path.isEmpty {
                legacyPaths.insert(URL(fileURLWithPath: path).standardizedFileURL.path)
                legacyPaths.insert(URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
            }
        }

        var detected = SpaceWallpapers.desktopAssignments(for: candidates)

        // Legacy single-file / per-screen fallback for video or GIF when the system
        // still-image store has no matching moonleaf wallpaper on an empty session list.
        if !inTestOverride && snapshot.sessions.isEmpty {
            let screenMap = MoonleafConfigStore.shared.readScreenWallpapers()
            if !screenMap.isEmpty {
                let screens = NSScreen.screens
                for (index, path) in screenMap {
                    guard screens.indices.contains(index),
                          let displayUUID = SpaceBinding.displayUUID(for: screens[index]),
                          let target = candidates.first(where: { $0.isCurrent && $0.displayUUIDs.contains(displayUUID) }),
                          detected[target.key] == nil else { continue }
                    detected[target.key] = path
                }
            }
            if let legacyCurrent = MoonleafConfigStore.shared.readCurrentWallpaper() {
                let display = SpaceBinding.currentDisplayUUID()
                if let current = candidates.first(where: { $0.isCurrent && (display == nil || $0.displayUUIDs.contains(display!)) })
                    ?? candidates.first(where: \.isCurrent),
                   detected[current.key] == nil {
                    detected[current.key] = legacyCurrent
                }
            }
        }

        var seeded: [(target: DesktopTarget, asset: AssetRecord, path: String)] = []
        for target in candidates {
            guard let rawPath = detected[target.key],
                  let ownedPath = resolvedOwnedPath(rawPath, snapshot: snapshot, legacyPaths: legacyPaths) else {
                continue
            }
            let name = URL(fileURLWithPath: ownedPath).deletingPathExtension().lastPathComponent
            let source = isInsideDirectory(ownedPath, directory: MoonleafConfigStore.libraryRoot) ? "library" : "external"
            let asset = catalog.ensureAsset(path: ownedPath, name: name, source: source, origin: "restore")
            seeded.append((target: target, asset: asset, path: ownedPath))
        }
        guard !seeded.isEmpty else { return }

        catalog.mutate { file in
            for item in seeded {
                guard !file.sessions.contains(where: { $0.targetKey == item.target.key }),
                      !file.suppressedRestoreKeys.contains(item.target.key) else { continue }
                file.sessions.append(TargetSession(
                    targetKey: item.target.key,
                    assetID: item.asset.id,
                    assetName: item.asset.name,
                    path: item.path,
                    listKind: nil,
                    playlistID: nil,
                    folderPath: nil,
                    includeSubdirectories: nil,
                    rotationEnabled: false,
                    paused: false,
                    pauseReason: nil,
                    order: "random",
                    interval: "5",
                    unavailable: false,
                    provenance: "moonleaf",
                    lastRotatedAt: nil
                ))
            }
        }
    }

    private func resolvedOwnedPath(_ rawPath: String, snapshot: CatalogFile, legacyPaths: Set<String>) -> String? {
        guard !rawPath.isEmpty else { return nil }
        let rawURL = URL(fileURLWithPath: rawPath).standardizedFileURL
        let rawResolved = rawURL.resolvingSymlinksInPath().path
        guard FileManager.default.fileExists(atPath: rawResolved) else { return nil }
        guard MediaKind.from(path: rawURL.path) != .unknown || MediaKind.from(path: rawResolved) != .unknown else {
            return nil
        }

        if let matchedAsset = snapshot.assets.first(where: {
            let assetStd = URL(fileURLWithPath: $0.path).standardizedFileURL.path
            let assetRes = URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path
            return assetStd == rawURL.path || assetRes == rawResolved
        }) {
            if FileManager.default.fileExists(atPath: matchedAsset.path) {
                return matchedAsset.path
            }
            return rawURL.path
        }

        if isInsideDirectory(rawURL.path, directory: MoonleafConfigStore.libraryRoot)
            || isInsideDirectory(rawResolved, directory: MoonleafConfigStore.libraryRoot) {
            return rawURL.path
        }

        if let future = snapshot.futureSaveDirectory, !future.isEmpty {
            let futureURL = URL(fileURLWithPath: future, isDirectory: true)
            if isInsideDirectory(rawURL.path, directory: futureURL)
                || isInsideDirectory(rawResolved, directory: futureURL) {
                return rawURL.path
            }
        }

        if legacyPaths.contains(rawURL.path) || legacyPaths.contains(rawResolved) {
            return rawURL.path
        }

        return nil
    }

    private func isInsideDirectory(_ path: String, directory: URL) -> Bool {
        let dirStd = directory.standardizedFileURL.path
        let dirRes = directory.resolvingSymlinksInPath().path
        let stdPrefix = dirStd.hasSuffix("/") ? dirStd : dirStd + "/"
        let resPrefix = dirRes.hasSuffix("/") ? dirRes : dirRes + "/"
        let pathStd = URL(fileURLWithPath: path).standardizedFileURL.path
        let pathRes = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return pathStd.hasPrefix(stdPrefix) || pathRes.hasPrefix(resPrefix)
    }

    private func pushAssignments(recordHistory: Bool) {
        guard canTouchApp || assignmentsSink != nil else { return }
        _ = recordHistory
        var file = PlaybackAssignmentFile(revision: Int(Date().timeIntervalSince1970), separateSpaces: separateSpaces, targets: [:])
        let snapshot = catalog.snapshot()
        var needsPlayer = false
        for session in snapshot.sessions where !session.unavailable {
            guard let path = session.path, FileManager.default.fileExists(atPath: path) else { continue }
            let kind = MediaKind.from(path: path)
            if kind.usesSpaceBoundOverlay { needsPlayer = true }
            file.targets[session.targetKey] = PlaybackAssignment(
                path: path,
                kind: kind.rawValue,
                paused: session.paused,
                manualPause: session.pauseReason == "manual",
                pauseReason: session.pauseReason
            )
        }
        for (key, request) in pendingByTarget where FileManager.default.fileExists(atPath: request.path) {
            let kind = MediaKind.from(path: request.path)
            if kind.usesSpaceBoundOverlay { needsPlayer = true }
            file.targets[key] = PlaybackAssignment(
                path: request.path,
                kind: kind.rawValue,
                paused: false,
                manualPause: false,
                pauseReason: nil,
                requestID: request.requestID,
                requestedAt: request.requestedAt
            )
        }
        if let assignmentsSink {
            assignmentsSink(file)
            return
        }
        SpaceBinding.writeAssignments(file)
        if needsPlayer {
            GlasswpProcessManager.shared.ensureRunning(perDesktopMode: true)
        }
        SpaceBinding.postReconcile()
    }

    private func readPlayerState() {
        acceptReported(SpaceBinding.readState())
    }

    func acceptReported(_ file: PlaybackStateFile?) {
        playerState = file?.targets ?? [:]
        guard let file, !pendingByTarget.isEmpty else { return }
        var unique: [String: PendingOverlay] = [:]
        for request in pendingByTarget.values {
            unique[request.requestID] = request
        }
        var failed = false
        var committed = false
        for request in unique.values {
            let keys = request.keys.filter { pendingByTarget[$0]?.requestID == request.requestID }
            guard !keys.isEmpty else { continue }
            let sawRequest = file.targets.values.contains { $0.requestID == request.requestID }
            if file.updatedAt.timeIntervalSince(request.requestedAt) < -1 && !sawRequest { continue }
            var succeeded: [String] = []
            var rejected: [String] = []
            var waiting = false
            for key in keys {
                guard let state = file.targets[key] else {
                    if sawRequest { rejected.append(key) } else { waiting = true }
                    continue
                }
                if ApplyCommit.overlaySucceeded(
                    requestID: request.requestID,
                    path: request.path,
                    requestedAt: request.requestedAt,
                    reportedRequestID: state.requestID,
                    reportedPath: state.path,
                    reportedAt: state.requestedAt,
                    bound: state.bound,
                    reason: state.reason
                ) {
                    succeeded.append(key)
                } else if ApplyCommit.overlayFailed(
                    requestID: request.requestID,
                    path: request.path,
                    requestedAt: request.requestedAt,
                    reportedRequestID: state.requestID,
                    reportedPath: state.path,
                    reportedAt: state.requestedAt,
                    bound: state.bound,
                    reason: state.reason
                ) {
                    rejected.append(key)
                } else {
                    waiting = true
                }
            }
            if waiting { continue }
            if !succeeded.isEmpty {
                commitOverlay(request, keys: succeeded)
                committed = true
            }
            for key in keys where pendingByTarget[key]?.requestID == request.requestID {
                pendingByTarget.removeValue(forKey: key)
            }
            if !rejected.isEmpty { failed = true }
        }
        if failed {
            statusMessage = NSLocalizedString("bind_failed", comment: "")
        } else if pendingByTarget.isEmpty {
            statusMessage = nil
        }
        if committed || failed {
            pushAssignments(recordHistory: false)
        }
        if committed, canTouchApp {
            publishCurrentPath()
        }
    }

    private func commitOverlay(_ pending: PendingOverlay, keys: [String]) {
        let keys = keys.filter { pendingByTarget[$0]?.requestID == pending.requestID }
        guard !keys.isEmpty else { return }
        catalog.mutate { file in
            for key in keys {
                var session = file.sessions.first(where: { $0.targetKey == key }) ?? TargetSession(
                    targetKey: key,
                    assetID: pending.assetID,
                    assetName: pending.assetName,
                    path: pending.path,
                    listKind: nil,
                    playlistID: nil,
                    folderPath: nil,
                    includeSubdirectories: nil,
                    rotationEnabled: false,
                    paused: false,
                    pauseReason: nil,
                    order: "sequential",
                    interval: "5",
                    unavailable: false,
                    provenance: "moonleaf",
                    lastRotatedAt: nil
                )
                session.assetID = pending.assetID
                session.assetName = pending.assetName
                session.path = pending.path
                session.unavailable = false
                session.provenance = "moonleaf"
                session.paused = false
                session.pauseReason = nil
                if pending.stopRotation {
                    session.rotationEnabled = false
                    session.listKind = nil
                    session.playlistID = nil
                } else if let stamp = pending.stamp {
                    session.listKind = stamp.kind
                    session.playlistID = stamp.playlistID
                    session.folderPath = stamp.folderPath
                    session.includeSubdirectories = stamp.includeSubdirectories
                    session.rotationEnabled = stamp.rotationEnabled
                    session.order = stamp.order
                    session.interval = stamp.interval
                }
                if pending.touchRotationClock {
                    session.lastRotatedAt = Date()
                }
                file.suppressedRestoreKeys.removeAll { $0 == key }
                if let index = file.sessions.firstIndex(where: { $0.targetKey == key }) {
                    file.sessions[index] = session
                } else {
                    file.sessions.append(session)
                }
            }
            if pending.recordHistory {
                file.history = HistoryLogic.appending(
                    file.history,
                    event: HistoryEvent(
                        id: UUID(),
                        assetID: pending.assetID,
                        assetName: pending.assetName,
                        appliedAt: Date(),
                        targetKeys: keys,
                        origin: pending.origin,
                        playlistID: pending.playlistID,
                        playlistName: pending.playlistName
                    ),
                    enabled: file.historyEnabled,
                    isRestore: false
                )
            }
        }
        reloadPublished()
        guard canTouchApp,
              let current = currentTarget(displayUUID: SpaceBinding.currentDisplayUUID()),
              keys.contains(current.key) else { return }
        MoonleafConfigStore.shared.writeCurrentWallpaperAsync(pending.path)
    }

    private func reloadPublished() {
        let snapshot = catalog.snapshot()
        sessions = snapshot.sessions
        playlists = snapshot.playlists
        history = snapshot.history
        historyEnabled = snapshot.historyEnabled
        catalogRevision += 1
        guard canTouchApp else { return }
        macpaperService.shared.favorites = catalog.favoritePaths()
    }

    func reloadForChecks() {
        reloadPublished()
        statusMessage = nil
    }

    private func publishCurrentPath() {
        guard canTouchApp else { return }
        let display = SpaceBinding.currentDisplayUUID()
        guard let target = currentTarget(displayUUID: display) else { return }
        let session = sessions.first(where: { $0.targetKey == target.key })
        macpaperService.shared.current_wp = session?.path ?? ""
    }

    private func mediaFiles(in directory: String, recursive: Bool) -> [String] {
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
            options: recursive ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }
        var paths: [String] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
            }
            if values?.isDirectory == true { continue }
            if MediaKind.from(path: url.path) != .unknown {
                paths.append(url.path)
            }
        }
        return paths.sorted()
    }

    private func intervalSeconds(_ raw: String) -> TimeInterval? {
        RotationSchedule.seconds(raw)
    }

    private func message(for error: ScopeError) -> String {
        switch error {
        case .noCurrentDesktop: return NSLocalizedString("scope_no_current", comment: "")
        case .crossDisplayNeedsConfirmation: return NSLocalizedString("scope_cross_display", comment: "")
        case .unknownTarget: return NSLocalizedString("scope_unknown_target", comment: "")
        }
    }

    private func pauseText(_ reason: String) -> String {
        switch reason {
        case "manual": return NSLocalizedString("pause_manual", comment: "")
        case "fullscreen": return NSLocalizedString("pause_fullscreen", comment: "")
        case "not-visible": return NSLocalizedString("pause_not_visible", comment: "")
        default: return NSLocalizedString("pause_manual", comment: "")
        }
    }
}
