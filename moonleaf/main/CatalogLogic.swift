//
//  CatalogLogic.swift
//  moonleaf
//
//  Pure rules for history, playlists, desktop targets and storage classification.
//  No AppKit: the engine and the unit checks share this file.
//

import Foundation

enum MediaKind: String, Codable, Equatable {
    case still
    case gif
    case video
    case unknown

    static func from(path: String) -> MediaKind {
        switch (path as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png": return .still
        case "gif": return .gif
        case "mp4", "mov": return .video
        default: return .unknown
        }
    }

    var usesSpaceBoundOverlay: Bool {
        self == .gif || self == .video
    }
}

struct HistoryEvent: Codable, Equatable, Identifiable {
    var id: UUID
    var assetID: UUID
    var assetName: String
    var appliedAt: Date
    /// One event even when several desktops were set together. The cap counts events, not targets or files.
    var targetKeys: [String]
    var origin: String
    var playlistID: UUID?
    var playlistName: String?

    static let limit = 1000
}

enum HistoryLogic {
    static func appending(
        _ events: [HistoryEvent],
        event: HistoryEvent,
        enabled: Bool,
        isRestore: Bool
    ) -> [HistoryEvent] {
        guard enabled, !isRestore, !event.targetKeys.isEmpty else { return events }
        var next = events
        next.append(event)
        if next.count > HistoryEvent.limit {
            next.removeFirst(next.count - HistoryEvent.limit)
        }
        return next
    }

    struct Deduped: Equatable {
        var assetID: UUID
        var assetName: String
        var latest: HistoryEvent
        var targetKeys: [String]
    }

    /// Most recent successful use of each asset. Targets belong to that use and can be expanded.
    static func deduped(_ events: [HistoryEvent]) -> [Deduped] {
        var seen = Set<UUID>()
        var rows: [Deduped] = []
        for event in events.reversed() {
            guard seen.insert(event.assetID).inserted else { continue }
            rows.append(Deduped(
                assetID: event.assetID,
                assetName: event.assetName,
                latest: event,
                targetKeys: event.targetKeys
            ))
        }
        return rows
    }

    static func timeline(_ events: [HistoryEvent], calendar: Calendar = .current) -> [(day: Date, events: [HistoryEvent])] {
        let grouped = Dictionary(grouping: events) { calendar.startOfDay(for: $0.appliedAt) }
        return grouped.keys.sorted(by: >).map { day in
            let items = grouped[day]!.sorted { $0.appliedAt > $1.appliedAt }
            return (day, items)
        }
    }

    static func filtered(
        _ events: [HistoryEvent],
        query: String,
        displayKeyPrefix: String?,
        spaceKey: String?,
        kind: MediaKind?
    ) -> [HistoryEvent] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return events.filter { event in
            if !needle.isEmpty {
                let name = event.assetName.lowercased()
                if !name.contains(needle) { return false }
            }
            if let displayKeyPrefix, !event.targetKeys.contains(where: { $0.hasPrefix(displayKeyPrefix) || $0 == displayKeyPrefix }) {
                return false
            }
            if let spaceKey, !event.targetKeys.contains(spaceKey) { return false }
            if let kind, MediaKind.from(path: event.assetName) != kind && kind != .unknown {
                // assetName is a display name, not a path. Kind filter is applied by the caller
                // when it has a path; this helper only filters when the name itself has an extension.
                let named = MediaKind.from(path: event.assetName)
                if named != .unknown && named != kind { return false }
            }
            return true
        }
    }
}

enum PlaylistLogic {
    static func adding(_ assetIDs: [UUID], to ordered: [UUID]) -> [UUID] {
        var seen = Set(ordered)
        var next = ordered
        for id in assetIDs where seen.insert(id).inserted {
            next.append(id)
        }
        return next
    }

    static func removing(_ assetID: UUID, from ordered: [UUID]) -> [UUID] {
        ordered.filter { $0 != assetID }
    }

    static func moving(_ ordered: [UUID], from: Int, to: Int) -> [UUID] {
        guard ordered.indices.contains(from), ordered.indices.contains(to), from != to else { return ordered }
        var next = ordered
        let item = next.remove(at: from)
        next.insert(item, at: to)
        return next
    }

    static func playable(_ ids: [UUID], isAvailable: (UUID) -> Bool) -> (ids: [UUID], skipped: Int) {
        let kept = ids.filter(isAvailable)
        return (kept, ids.count - kept.count)
    }

    /// Sequential walks the playable list. Random avoids the current id when another exists.
    static func nextID(
        playable: [UUID],
        current: UUID?,
        order: String,
        randomIndex: (Int) -> Int
    ) -> UUID? {
        guard !playable.isEmpty else { return nil }
        if order == "sequential" {
            if let current, let index = playable.firstIndex(of: current) {
                return playable[(index + 1) % playable.count]
            }
            return playable[0]
        }
        if playable.count == 1 { return playable[0] }
        let pool = playable.filter { $0 != current }
        let choices = pool.isEmpty ? playable : pool
        let index = min(max(0, randomIndex(choices.count)), choices.count - 1)
        return choices[index]
    }
}

struct SpaceFact: Equatable {
    var displayUUID: String
    var displayName: String
    var spaceUUID: String
    var managedID: UInt64
    var isCurrent: Bool
    var type: Int
}

struct DesktopTarget: Equatable, Identifiable {
    var key: String
    var displayUUIDs: [String]
    var displayName: String
    var spaceUUID: String
    var spaceIndex: Int
    var isCurrent: Bool
    var managedIDs: [UInt64]
    var separateSpaces: Bool

    var id: String { key }
}

enum TargetLogic {
    /// User desktops only. Shared-space mode collapses a space that spans displays into one target.
    /// Separate-space mode emits only combinations the live list actually contains.
    static func targets(spaces: [SpaceFact], separateSpaces: Bool) -> [DesktopTarget] {
        let user = spaces.filter { $0.type == 0 }
        if !separateSpaces {
            var order: [String] = []
            var grouped: [String: [SpaceFact]] = [:]
            for space in user {
                if grouped[space.spaceUUID] == nil { order.append(space.spaceUUID) }
                grouped[space.spaceUUID, default: []].append(space)
            }
            return order.enumerated().map { index, uuid in
                let members = grouped[uuid] ?? []
                let names = uniqueNames(members.map(\.displayName))
                return DesktopTarget(
                    key: "span:\(uuid)",
                    displayUUIDs: unique(members.map(\.displayUUID)),
                    displayName: names.joined(separator: " + "),
                    spaceUUID: uuid,
                    spaceIndex: index + 1,
                    isCurrent: members.contains(where: \.isCurrent),
                    managedIDs: members.map(\.managedID),
                    separateSpaces: false
                )
            }
        }

        var displayOrder: [String] = []
        for space in user where !displayOrder.contains(space.displayUUID) {
            displayOrder.append(space.displayUUID)
        }
        var result: [DesktopTarget] = []
        for displayUUID in displayOrder {
            let onDisplay = user.filter { $0.displayUUID == displayUUID }
            for (index, space) in onDisplay.enumerated() {
                result.append(DesktopTarget(
                    key: "d:\(displayUUID)|s:\(space.spaceUUID)",
                    displayUUIDs: [displayUUID],
                    displayName: space.displayName,
                    spaceUUID: space.spaceUUID,
                    spaceIndex: index + 1,
                    isCurrent: space.isCurrent,
                    managedIDs: [space.managedID],
                    separateSpaces: true
                ))
            }
        }
        return result
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func uniqueNames(_ values: [String]) -> [String] {
        unique(values.filter { !$0.isEmpty })
    }
}

enum ScopeKind: String, Equatable {
    case currentDesktop
    case displayDesktops
    case explicit
}

enum ScopeError: Error, Equatable {
    case noCurrentDesktop
    case crossDisplayNeedsConfirmation
    case unknownTarget
}

enum ScopeLogic {
    static func resolve(
        kind: ScopeKind,
        targets: [DesktopTarget],
        displayUUID: String?,
        explicitKeys: [String],
        allowCrossDisplay: Bool
    ) -> Result<[DesktopTarget], ScopeError> {
        switch kind {
        case .currentDesktop:
            let current = targets.filter(\.isCurrent)
            let scoped: [DesktopTarget]
            if let displayUUID {
                scoped = current.filter { $0.displayUUIDs.contains(displayUUID) }
            } else {
                scoped = current
            }
            guard !scoped.isEmpty else { return .failure(.noCurrentDesktop) }
            if !allowCrossDisplay && spansDisplays(scoped, source: displayUUID) {
                return .failure(.crossDisplayNeedsConfirmation)
            }
            return .success(scoped)
        case .displayDesktops:
            guard let displayUUID else { return .failure(.noCurrentDesktop) }
            let scoped = targets.filter { $0.displayUUIDs.contains(displayUUID) }
            guard !scoped.isEmpty else { return .failure(.noCurrentDesktop) }
            if !allowCrossDisplay && spansDisplays(scoped, source: displayUUID) {
                return .failure(.crossDisplayNeedsConfirmation)
            }
            return .success(scoped)
        case .explicit:
            let scoped = targets.filter { explicitKeys.contains($0.key) }
            guard scoped.count == Set(explicitKeys).count, !scoped.isEmpty else {
                return .failure(.unknownTarget)
            }
            if !allowCrossDisplay && spansDisplays(scoped, source: displayUUID) {
                return .failure(.crossDisplayNeedsConfirmation)
            }
            return .success(scoped)
        }
    }

    private static func spansDisplays(_ targets: [DesktopTarget], source: String?) -> Bool {
        if targets.allSatisfy({ !$0.separateSpaces }) { return false }
        if let source {
            return targets.contains { target in
                target.separateSpaces && !target.displayUUIDs.contains(source)
            }
        }
        return Set(targets.filter(\.separateSpaces).flatMap(\.displayUUIDs)).count > 1
    }
}

struct FileFact: Equatable {
    var path: String
    var isSymlink: Bool
    var byteSize: Int64?
    var insideLibrary: Bool
}

enum StorageLogic {
    /// Symlinks are external references. Their targets are not exclusive app usage.
    /// A library file with an unknown size makes the library total unknown rather than zero.
    static func summarize(_ files: [FileFact]) -> (libraryBytes: Int64?, libraryKnown: Bool, externalPaths: [String]) {
        var bytes: Int64 = 0
        var known = true
        var external: [String] = []
        for file in files {
            if file.isSymlink || !file.insideLibrary {
                external.append(file.path)
                continue
            }
            guard let size = file.byteSize else {
                known = false
                continue
            }
            bytes += size
        }
        return (known ? bytes : nil, known, external)
    }
}
