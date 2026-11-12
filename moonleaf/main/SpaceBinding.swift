//
//  SpaceBinding.swift
//  moonleaf
//
//  Live display/Space identity and space-bound window assignment.
//  Compiled into both the manager and glasswp.
//

import AppKit
import Darwin
import Foundation

struct PlaybackAssignment: Codable, Equatable {
    var path: String
    var kind: String
    var paused: Bool
    var manualPause: Bool
    var pauseReason: String?
    var requestID: String
    var requestedAt: Date

    init(
        path: String,
        kind: String,
        paused: Bool,
        manualPause: Bool,
        pauseReason: String?,
        requestID: String = UUID().uuidString,
        requestedAt: Date = Date()
    ) {
        self.path = path
        self.kind = kind
        self.paused = paused
        self.manualPause = manualPause
        self.pauseReason = pauseReason
        self.requestID = requestID
        self.requestedAt = requestedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        kind = try container.decode(String.self, forKey: .kind)
        paused = try container.decode(Bool.self, forKey: .paused)
        manualPause = try container.decode(Bool.self, forKey: .manualPause)
        pauseReason = try container.decodeIfPresent(String.self, forKey: .pauseReason)
        requestID = try container.decodeIfPresent(String.self, forKey: .requestID) ?? ""
        requestedAt = try container.decodeIfPresent(Date.self, forKey: .requestedAt) ?? .distantPast
    }
}

struct PlaybackAssignmentFile: Codable, Equatable {
    var revision: Int
    var separateSpaces: Bool
    var targets: [String: PlaybackAssignment]
}

struct PlaybackTargetState: Codable, Equatable {
    var path: String
    var playing: Bool
    var paused: Bool
    var reason: String?
    var bound: Bool
    var requestID: String
    var requestedAt: Date

    init(
        path: String,
        playing: Bool,
        paused: Bool,
        reason: String?,
        bound: Bool,
        requestID: String = "",
        requestedAt: Date = .distantPast
    ) {
        self.path = path
        self.playing = playing
        self.paused = paused
        self.reason = reason
        self.bound = bound
        self.requestID = requestID
        self.requestedAt = requestedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        playing = try container.decode(Bool.self, forKey: .playing)
        paused = try container.decode(Bool.self, forKey: .paused)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        bound = try container.decode(Bool.self, forKey: .bound)
        requestID = try container.decodeIfPresent(String.self, forKey: .requestID) ?? ""
        requestedAt = try container.decodeIfPresent(Date.self, forKey: .requestedAt) ?? .distantPast
    }
}

struct PlaybackStateFile: Codable, Equatable {
    var updatedAt: Date
    var targets: [String: PlaybackTargetState]
}

enum PlaybackNotices {
    static let reconcile = Notification.Name("com.naomisphere.moonleaf.reconcilePlayback")
    static let state = Notification.Name("com.naomisphere.moonleaf.playbackState")
}

enum PlaybackFiles {
    static var assignments: URL {
        MoonleafConfigStore.configRoot.appendingPathComponent("playback-assignments.json")
    }
    static var state: URL {
        MoonleafConfigStore.configRoot.appendingPathComponent("playback-state.json")
    }
}

enum SpaceBinding {
    /// Tests substitute live Space facts. Production leaves this nil.
    static var factsOverride: [SpaceFact]?
    private static let skyLight = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    static func spansDisplays() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.spaces.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let spans = plist["spans-displays"] as? Bool else {
            return false
        }
        return spans
    }

    static func separateSpacesEnabled() -> Bool {
        !spansDisplays()
    }

    static func liveFacts() -> [SpaceFact] {
        if let factsOverride { return factsOverride }
        guard let skyLight,
              let connectionSymbol = dlsym(skyLight, "SLSMainConnectionID"),
              let copySymbol = dlsym(skyLight, "SLSCopyManagedDisplaySpaces") else { return [] }

        typealias ConnectionFn = @convention(c) () -> Int32
        typealias CopyDisplaysFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
        let connection = unsafeBitCast(connectionSymbol, to: ConnectionFn.self)()
        guard let displays = unsafeBitCast(copySymbol, to: CopyDisplaysFn.self)(connection)?
            .takeRetainedValue() as? [[String: Any]] else { return [] }

        var facts: [SpaceFact] = []
        for display in displays {
            guard let displayUUID = display["Display Identifier"] as? String,
                  let entries = display["Spaces"] as? [[String: Any]] else { continue }
            let current = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? UInt64
            let name = screenName(for: displayUUID)
            for entry in entries {
                guard let uuid = entry["uuid"] as? String,
                      let managed = entry["ManagedSpaceID"] as? UInt64 else { continue }
                let type = entry["type"] as? Int ?? 0
                facts.append(SpaceFact(
                    displayUUID: displayUUID,
                    displayName: name,
                    spaceUUID: uuid,
                    managedID: managed,
                    isCurrent: current == managed,
                    type: type
                ))
            }
        }
        return facts
    }

    static func liveTargets() -> (separate: Bool, targets: [DesktopTarget]) {
        let separate = separateSpacesEnabled()
        return (separate, TargetLogic.targets(spaces: liveFacts(), separateSpaces: separate))
    }

    static func currentDisplayUUID() -> String? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        return screen.flatMap(displayUUID(for:))
    }

    static func displayUUID(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        let uuid = CGDisplayCreateUUIDFromDisplayID(number).takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func screen(for displayUUID: String) -> NSScreen? {
        NSScreen.screens.first { self.displayUUID(for: $0) == displayUUID }
    }

    static func screenName(for displayUUID: String) -> String {
        screen(for: displayUUID)?.localizedName ?? "Display"
    }

    /// Moves a window onto a Mission Control space. The window must not join all spaces.
    @discardableResult
    static func move(window: NSWindow, to managedID: UInt64) -> Bool {
        guard let skyLight,
              let connectionSymbol = dlsym(skyLight, "SLSMainConnectionID"),
              let moveSymbol = dlsym(skyLight, "SLSMoveWindowsToManagedSpace") else { return false }
        typealias ConnectionFn = @convention(c) () -> Int32
        typealias MoveFn = @convention(c) (Int32, CFArray, UInt64) -> Int32
        let connection = unsafeBitCast(connectionSymbol, to: ConnectionFn.self)()
        let ids = [NSNumber(value: window.windowNumber)] as CFArray
        let move = unsafeBitCast(moveSymbol, to: MoveFn.self)
        return move(connection, ids, managedID) == 0
    }
    static func readAssignments() -> PlaybackAssignmentFile {
        guard let data = try? Data(contentsOf: PlaybackFiles.assignments) else {
            return PlaybackAssignmentFile(revision: 0, separateSpaces: separateSpacesEnabled(), targets: [:])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(PlaybackAssignmentFile.self, from: data) else {
            return PlaybackAssignmentFile(revision: 0, separateSpaces: separateSpacesEnabled(), targets: [:])
        }
        return decoded
    }

    static func writeAssignments(_ file: PlaybackAssignmentFile) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(file) else { return }
        try? FileManager.default.createDirectory(
            at: MoonleafConfigStore.configRoot,
            withIntermediateDirectories: true
        )
        try? data.write(to: PlaybackFiles.assignments, options: .atomic)
    }

    static func readState() -> PlaybackStateFile? {
        guard let data = try? Data(contentsOf: PlaybackFiles.state) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PlaybackStateFile.self, from: data)
    }

    static func writeState(_ file: PlaybackStateFile) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(file) else { return }
        try? FileManager.default.createDirectory(
            at: MoonleafConfigStore.configRoot,
            withIntermediateDirectories: true
        )
        try? data.write(to: PlaybackFiles.state, options: .atomic)
    }

    static func postReconcile() {
        DistributedNotificationCenter.default().postNotificationName(
            PlaybackNotices.reconcile,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    static func postState() {
        DistributedNotificationCenter.default().postNotificationName(
            PlaybackNotices.state,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
