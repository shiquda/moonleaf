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
    }
    func refreshTopology(restoreMatching: Bool) {
        let live = SpaceBinding.liveTargets()
        separateSpaces = live.separate
        targets = live.targets
        let liveKeys = Set(live.targets.map(\.key))
        if catalog.snapshot().sessions.isEmpty {
            seedCurrent(targets: live.targets)
        }
        catalog.mutate { file in
            for index in file.sessions.indices {
                file.sessions[index].unavailable = !liveKeys.contains(file.sessions[index].targetKey)
            }
        }
        reloadPublished()
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
        playlistName: String? = nil
    ) -> Bool {
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
            let asset = catalog.ensureAsset(
                path: path,
                name: name,
                source: path.hasPrefix(MoonleafConfigStore.libraryRoot.path) ? "library" : "external",
                origin: origin
            )
            var snapshot = catalog.snapshot()
            var appliedKeys: [String] = []
            for target in chosen {
                if !applyOne(
                    asset: asset,
                    path: path,
                    kind: kind,
                    target: target,
                    snapshot: &snapshot,
                    stopRotation: stopRotation
                ) {
                    continue
                }
                appliedKeys.append(target.key)
            }
            guard !appliedKeys.isEmpty else {
                statusMessage = NSLocalizedString("apply_none", comment: "")
                return false
            }
            if recordHistory {
                let event = HistoryEvent(
                    id: UUID(),
                    assetID: asset.id,
                    assetName: asset.name,
                    appliedAt: Date(),
                    targetKeys: appliedKeys,
                    origin: origin,
                    playlistID: playlistID,
                    playlistName: playlistName
                )
                snapshot.history = HistoryLogic.appending(
                    snapshot.history,
                    event: event,
                    enabled: snapshot.historyEnabled,
                    isRestore: false
                )
            }
            catalog.mutate { $0 = snapshot }
            reloadPublished()
            pushAssignments(recordHistory: false)
            publishCurrentPath()
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
        let ok = apply(
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
            playlistName: list.name
        )
        guard ok else { return false }
        catalog.mutate { file in
            guard let index = file.sessions.firstIndex(where: { $0.targetKey == targetKey }) else { return }
            file.sessions[index].listKind = "playlist"
            file.sessions[index].playlistID = list.id
            file.sessions[index].rotationEnabled = true
            file.sessions[index].order = existing?.order ?? list.order
            file.sessions[index].interval = existing?.interval ?? list.interval
            file.sessions[index].paused = false
            file.sessions[index].pauseReason = nil
        }
        reloadPublished()
        pushAssignments(recordHistory: false)
        return true
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
        let ok = apply(
            path: first.path,
            name: first.name,
            scope: .explicit,
            displayUUID: target.displayUUIDs.first,
            explicitKeys: [targetKey],
            stopRotation: false,
            origin: "manual",
            confirmedCrossDisplay: true,
            recordHistory: true
        )
        guard ok else { return false }
        catalog.mutate { file in
            guard let index = file.sessions.firstIndex(where: { $0.targetKey == targetKey }) else { return }
            file.sessions[index].listKind = kind
            file.sessions[index].playlistID = nil
            file.sessions[index].folderPath = folderPath
            file.sessions[index].includeSubdirectories = includeSubdirectories
            file.sessions[index].rotationEnabled = true
            file.sessions[index].order = existing?.order ?? "random"
            file.sessions[index].interval = existing?.interval ?? UserDefaults.standard.string(forKey: "moonleaf_shuffleInterval") ?? "5"
        }
        reloadPublished()
        return true
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
        catalog.mutate { file in
            file.sessions.removeAll { $0.targetKey == key }
        }
        reloadPublished()
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

    func rotateDueSessions() {
        let libraryShuffle = UserDefaults.standard.bool(forKey: "moonleaf_shuffleEnabled")
        let now = Date()
        for session in sessions where session.rotationEnabled && !session.paused && !session.unavailable {
            if (session.listKind == nil || session.listKind == "library") && !libraryShuffle { continue }
            let interval = intervalSeconds(session.interval) ?? 300
            let last = session.lastRotatedAt ?? .distantPast
            if now.timeIntervalSince(last) >= interval {
                advance(session, origin: "automatic")
            }
        }
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
        catalog.mutate { file in
            guard let index = file.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
            var ids: [UUID] = []
            for path in paths {
                let record = LibraryCatalog.shared.ensureAsset(
                    path: path,
                    name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                    source: path.hasPrefix(MoonleafConfigStore.libraryRoot.path) ? "library" : "external",
                    origin: nil
                )
                ids.append(record.id)
            }
            file.playlists[index].assetIDs = PlaylistLogic.adding(ids, to: file.playlists[index].assetIDs)
        }
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
            playlistName: playlists.first { $0.id == session.playlistID }?.name
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

    private func applyOne(
        asset: AssetRecord,
        path: String,
        kind: MediaKind,
        target: DesktopTarget,
        snapshot: inout CatalogFile,
        stopRotation: Bool
    ) -> Bool {
        if kind == .still {
            assignStill(path, target: target)
        }
        if let index = snapshot.sessions.firstIndex(where: { $0.targetKey == target.key }) {
            snapshot.sessions[index].assetID = asset.id
            snapshot.sessions[index].assetName = asset.name
            snapshot.sessions[index].path = path
            snapshot.sessions[index].unavailable = false
            snapshot.sessions[index].provenance = "moonleaf"
            snapshot.sessions[index].paused = false
            snapshot.sessions[index].pauseReason = nil
            if stopRotation {
                snapshot.sessions[index].rotationEnabled = false
                snapshot.sessions[index].listKind = nil
                snapshot.sessions[index].playlistID = nil
            }
        } else {
            snapshot.sessions.append(TargetSession(
                targetKey: target.key,
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
            ))
        }
        return true
    }

    private func assignStill(_ path: String, target: DesktopTarget) {
        let url = URL(fileURLWithPath: path)
        let spaces = SpaceWallpapers.liveSpaces().filter { space in
            space.uuid == target.spaceUUID && target.displayUUIDs.contains(space.displayUUID)
        }
        if !spaces.isEmpty {
            var assigned: [SpaceWallpapers.Space: String] = [:]
            for space in spaces { assigned[space] = path }
            SpaceWallpapers.assign(assigned)
            if spaces.contains(where: { !$0.isCurrent }) {
                SpaceWallpapers.reload()
            }
        }
        if target.isCurrent {
            for displayUUID in target.displayUUIDs {
                guard let screen = SpaceBinding.screen(for: displayUUID) else { continue }
                try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            }
        }
    }

    private func seedCurrent(targets: [DesktopTarget]) {
        guard let path = MoonleafConfigStore.shared.readCurrentWallpaper(),
              FileManager.default.fileExists(atPath: path),
              MediaKind.from(path: path) != .unknown else { return }
        let display = SpaceBinding.currentDisplayUUID()
        let current = targets.first(where: { $0.isCurrent && (display == nil || $0.displayUUIDs.contains(display!)) })
            ?? targets.first(where: \.isCurrent)
        guard let current else { return }
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let asset = catalog.ensureAsset(path: path, name: name, source: "library", origin: "restore")
        catalog.mutate { file in
            guard file.sessions.isEmpty else { return }
            file.sessions.append(TargetSession(
                targetKey: current.key,
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
                interval: "5",
                unavailable: false,
                provenance: "moonleaf",
                lastRotatedAt: nil
            ))
        }
    }

    private func pushAssignments(recordHistory: Bool) {
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
        SpaceBinding.writeAssignments(file)
        if needsPlayer {
            GlasswpProcessManager.shared.ensureRunning(perDesktopMode: true)
        }
        SpaceBinding.postReconcile()
    }

    private func readPlayerState() {
        playerState = SpaceBinding.readState()?.targets ?? [:]
        if playerState.values.contains(where: { !$0.bound && $0.reason == "space-bind-failed" }) {
            statusMessage = NSLocalizedString("bind_failed", comment: "")
        }
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

    private func publishCurrentPath() {
        let display = SpaceBinding.currentDisplayUUID()
        guard let target = currentTarget(displayUUID: display),
              let session = sessions.first(where: { $0.targetKey == target.key }) else { return }
        macpaperService.shared.current_wp = session.path ?? ""
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
        switch raw {
        case "1": return 60
        case "5": return 300
        case "10": return 600
        case "30": return 1800
        case "60": return 3600
        default: return nil
        }
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
