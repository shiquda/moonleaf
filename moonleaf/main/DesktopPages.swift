//
//  DesktopPages.swift
//  moonleaf
//
//  Usage, playlists and the shared asset detail. These pages read the same
//  coordinator the menu bar uses.
//

import AVFoundation
import ImageIO
import SwiftUI

enum AppPage: String, CaseIterable, Identifiable {
    case usage
    case library
    case playlists
    case discover
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usage: return NSLocalizedString("page_usage", comment: "")
        case .library: return NSLocalizedString("page_library", comment: "")
        case .playlists: return NSLocalizedString("page_playlists", comment: "")
        case .discover: return NSLocalizedString("page_discover", comment: "")
        case .settings: return NSLocalizedString("page_settings", comment: "")
        }
    }

    var symbol: String {
        switch self {
        case .usage: return "clock"
        case .library: return "square.grid.2x2"
        case .playlists: return "list.bullet"
        case .discover: return "sparkle.magnifyingglass"
        case .settings: return "gearshape"
        }
    }
}

final class AppNavigation: ObservableObject {
    static let shared = AppNavigation()
    @Published var page: AppPage = .usage
}

struct SidebarView: View {
    @ObservedObject private var navigation = AppNavigation.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(AppPage.allCases) { page in
                Button {
                    navigation.page = page
                } label: {
                    Label(page.title, systemImage: page.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(navigation.page == page ? Color.primary.opacity(0.12) : Color.clear)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(page.title)
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 196)
        .background(Color.primary.opacity(0.04))
    }
}

struct UsagePage: View {
    @ObservedObject private var playback = PlaybackCoordinator.shared
    @State private var query = ""
    @State private var displayFilter = ""
    @State private var spaceFilter = ""
    @State private var kindFilter = "all"
    @State private var timeline = false
    @State private var detailPath: String?
    @State private var confirmClear = false
    @State private var confirmCrossDisplay = false
    @State private var pendingCrossPath: String?
    @State private var pendingCrossName: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(playback.separateSpaces
                     ? NSLocalizedString("spaces_separate", comment: "")
                     : NSLocalizedString("spaces_shared", comment: ""))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let status = playback.statusMessage {
                    Text(status).foregroundStyle(.orange)
                }
                Text(NSLocalizedString("section_desktops", comment: ""))
                    .font(.headline)
                ForEach(grouped.keys.sorted(), id: \.self) { display in
                    Text(display).font(.subheadline.weight(.semibold))
                    ForEach(grouped[display] ?? []) { target in
                        desktopRow(target)
                    }
                }
                historySection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: detailBinding) { item in
            AssetDetailSheet(path: item.path)
        }
        .alert(NSLocalizedString("history_clear_title", comment: ""), isPresented: $confirmClear) {
            Button(NSLocalizedString("history_clear", comment: ""), role: .destructive) {
                playback.clearHistory()
            }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("history_clear_message", comment: ""))
        }
        .alert(NSLocalizedString("scope_cross_display", comment: ""), isPresented: $confirmCrossDisplay) {
            Button(NSLocalizedString("apply_confirm", comment: "")) {
                if let path = pendingCrossPath {
                    _ = playback.apply(
                        path: path,
                        name: pendingCrossName,
                        scope: .explicit,
                        displayUUID: SpaceBinding.currentDisplayUUID(),
                        explicitKeys: playback.targets.map(\.key),
                        stopRotation: true,
                        origin: "manual",
                        confirmedCrossDisplay: true,
                        recordHistory: true
                    )
                }
            }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
        }
    }

    private var grouped: [String: [DesktopTarget]] {
        Dictionary(grouping: playback.targets, by: \.displayName)
    }

    private var detailBinding: Binding<PathItem?> {
        Binding(
            get: { detailPath.map(PathItem.init) },
            set: { detailPath = $0?.path }
        )
    }

    private func desktopRow(_ target: DesktopTarget) -> some View {
        let session = playback.session(for: target.key)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(format: NSLocalizedString("desktop_n", comment: ""), target.spaceIndex))
                    .font(.body.weight(.medium))
                if target.isCurrent {
                    Text(NSLocalizedString("desktop_current", comment: ""))
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(4)
                }
                if playback.targetUnavailable(target.key) {
                    Text(NSLocalizedString("target_unavailable", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text(playback.playbackDescription(for: target.key))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(session?.assetName ?? NSLocalizedString("desktop_unset", comment: ""))
                .lineLimit(2)
            Text(session?.path ?? "")
                .font(.caption)
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
            HStack {
                Button(NSLocalizedString("pause_toggle", comment: "")) {
                    let paused = session?.paused == true
                    playback.setPaused(!paused, targetKey: target.key)
                }
                .disabled(playback.targetUnavailable(target.key))
                Button(NSLocalizedString("next_item", comment: "")) {
                    playback.next(targetKey: target.key)
                }
                .disabled(playback.targetUnavailable(target.key))
                if let path = session?.path {
                    Button(NSLocalizedString("detail_open", comment: "")) { detailPath = path }
                    Button(NSLocalizedString("reveal_finder", comment: "")) { reveal(path) }
                    Button(NSLocalizedString("copy_path", comment: "")) { copy(path) }
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(10)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("section_history", comment: "")).font(.headline)
            Text(String(format: NSLocalizedString("history_count", comment: ""), playback.history.count, HistoryEvent.limit))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(NSLocalizedString("search_name", comment: ""), text: $query)
                .textFieldStyle(.roundedBorder)
            HStack {
                Picker(NSLocalizedString("filter_display", comment: ""), selection: $displayFilter) {
                    Text(NSLocalizedString("filter_all", comment: "")).tag("")
                    ForEach(displayChoices, id: \.self) { Text($0).tag($0) }
                }
                Picker(NSLocalizedString("filter_desktop", comment: ""), selection: $spaceFilter) {
                    Text(NSLocalizedString("filter_all", comment: "")).tag("")
                    ForEach(playback.targets) { target in
                        Text("\(target.displayName) \(target.spaceIndex)").tag(target.key)
                    }
                }
                Picker(NSLocalizedString("filter_kind", comment: ""), selection: $kindFilter) {
                    Text(NSLocalizedString("filter_all", comment: "")).tag("all")
                    Text(NSLocalizedString("kind_still", comment: "")).tag("still")
                    Text(NSLocalizedString("kind_video", comment: "")).tag("video")
                    Text("GIF").tag("gif")
                }
                Toggle(NSLocalizedString("history_timeline", comment: ""), isOn: $timeline)
                Toggle(NSLocalizedString("history_enabled", comment: ""), isOn: Binding(
                    get: { playback.historyEnabled },
                    set: { playback.setHistoryEnabled($0) }
                ))
            }
            Button(NSLocalizedString("history_clear", comment: "")) { confirmClear = true }
                .disabled(playback.history.isEmpty)
            if timeline {
                ForEach(HistoryLogic.timeline(filteredHistory), id: \.day) { group in
                    Text(group.day.formatted(date: .abbreviated, time: .omitted)).font(.subheadline)
                    ForEach(group.events) { event in historyRow(event) }
                }
            } else {
                ForEach(HistoryLogic.deduped(filteredHistory), id: \.assetID) { row in
                    historyRow(row.latest)
                }
            }
        }
    }

    private var displayChoices: [String] {
        Array(Set(playback.targets.map(\.displayName))).sorted()
    }

    private var filteredHistory: [HistoryEvent] {
        playback.history.filter { event in
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !needle.isEmpty && !event.assetName.lowercased().contains(needle) { return false }
            if !displayFilter.isEmpty {
                let keys = playback.targets.filter { $0.displayName == displayFilter }.map(\.key)
                if !event.targetKeys.contains(where: { keys.contains($0) }) { return false }
            }
            if !spaceFilter.isEmpty && !event.targetKeys.contains(spaceFilter) { return false }
            if kindFilter != "all" {
                let path = playback.resolvedPath(assetID: event.assetID) ?? event.assetName
                if MediaKind.from(path: path).rawValue != kindFilter { return false }
            }
            return true
        }
    }

    private func historyRow(_ event: HistoryEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.assetName).font(.body)
            Text(event.appliedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(targetSummary(event.targetKeys))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(event.origin == "automatic" ? NSLocalizedString("origin_auto", comment: "") : NSLocalizedString("origin_manual", comment: ""))
                    .font(.caption)
                if let list = event.playlistName { Text(list).font(.caption) }
                Spacer()
                Button(NSLocalizedString("history_remove", comment: "")) { playback.removeHistory(event.id) }
                if let path = playback.resolvedPath(assetID: event.assetID) {
                    Button(NSLocalizedString("detail_open", comment: "")) { detailPath = path }
                }
            }
        }
        .padding(8)
    }

    private func targetSummary(_ keys: [String]) -> String {
        keys.map { key in
            if let target = playback.targets.first(where: { $0.key == key }) {
                return "\(target.displayName) \(target.spaceIndex)"
            }
            return NSLocalizedString("target_unavailable", comment: "")
        }.joined(separator: ", ")
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func copy(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }
}

private struct PathItem: Identifiable {
    var path: String
    var id: String { path }
}

struct PlaylistsPage: View {
    @ObservedObject private var playback = PlaybackCoordinator.shared
    @State private var newName = ""
    @State private var selectedID: UUID?
    @State private var confirmDelete = false
    @State private var targetKey = ""

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField(NSLocalizedString("playlist_name", comment: ""), text: $newName)
                    Button(NSLocalizedString("playlist_create", comment: "")) {
                        if let id = playback.createPlaylist(name: newName) {
                            selectedID = id
                            newName = ""
                        }
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                List(playback.playlists, selection: $selectedID) { list in
                    Text(list.name).tag(list.id)
                }
                if let id = selectedID {
                    Button(NSLocalizedString("playlist_delete", comment: ""), role: .destructive) {
                        confirmDelete = true
                    }
                    .alert(NSLocalizedString("playlist_delete_title", comment: ""), isPresented: $confirmDelete) {
                        Button(NSLocalizedString("playlist_delete", comment: ""), role: .destructive) {
                            playback.deletePlaylist(id)
                            selectedID = nil
                        }
                        Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
                    } message: {
                        Text(NSLocalizedString("playlist_delete_message", comment: ""))
                    }
                }
            }
            .padding(16)
            .frame(width: 280)
            Divider()
            if let list = playback.playlists.first(where: { $0.id == selectedID }) {
                playlistDetail(list)
            } else {
                Text(NSLocalizedString("playlist_pick", comment: ""))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func playlistDetail(_ list: NamedPlaylist) -> some View {
        let available = list.assetIDs.compactMap { playback.resolvedPath(assetID: $0) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(list.name).font(.title3)
                Text(String(format: NSLocalizedString("playlist_available", comment: ""), available.count, list.assetIDs.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(NSLocalizedString("playlist_order", comment: ""), selection: Binding(
                    get: { list.order },
                    set: { playback.updatePlaylistSettings(list.id, order: $0, interval: list.interval) }
                )) {
                    Text(NSLocalizedString("order_sequential", comment: "")).tag("sequential")
                    Text(NSLocalizedString("order_random", comment: "")).tag("random")
                }
                Picker(NSLocalizedString("playlist_interval", comment: ""), selection: Binding(
                    get: { list.interval },
                    set: { playback.updatePlaylistSettings(list.id, order: list.order, interval: $0) }
                )) {
                    ForEach(macpaperService.ShuffleInterval.allCases, id: \.rawValue) { interval in
                        Text(interval.displayName).tag(interval.rawValue)
                    }
                }
                Picker(NSLocalizedString("playlist_assign_target", comment: ""), selection: $targetKey) {
                    Text(NSLocalizedString("playlist_pick_target", comment: "")).tag("")
                    ForEach(playback.targets) { target in
                        Text("\(target.displayName) \(target.spaceIndex)").tag(target.key)
                    }
                }
                Button(NSLocalizedString("playlist_assign", comment: "")) {
                    guard !targetKey.isEmpty else { return }
                    if !playback.assignList(playlistID: list.id, targetKey: targetKey), let message = playback.statusMessage {
                        let alert = NSAlert()
                        alert.messageText = message
                        alert.runModal()
                    }
                }
                .disabled(targetKey.isEmpty || playback.targetUnavailable(targetKey))
                ForEach(Array(list.assetIDs.enumerated()), id: \.element) { index, assetID in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(playback.resolvedPath(assetID: assetID).map { URL(fileURLWithPath: $0).lastPathComponent } ?? NSLocalizedString("asset_missing", comment: ""))
                            Text(playback.resolvedPath(assetID: assetID) ?? "")
                                .font(.caption)
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(NSLocalizedString("playlist_up", comment: "")) {
                            playback.moveInPlaylist(playlistID: list.id, from: index, to: max(0, index - 1))
                        }
                        .disabled(index == 0)
                        Button(NSLocalizedString("playlist_down", comment: "")) {
                            playback.moveInPlaylist(playlistID: list.id, from: index, to: min(list.assetIDs.count - 1, index + 1))
                        }
                        .disabled(index == list.assetIDs.count - 1)
                        Button(NSLocalizedString("playlist_remove_item", comment: "")) {
                            playback.removeFromPlaylist(assetID: assetID, playlistID: list.id)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AssetDetailSheet: View {
    let path: String
    @ObservedObject private var playback = PlaybackCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    @State private var pixelSize = ""
    @State private var byteSize = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                .font(.title3)
            Text(path).textSelection(.enabled).font(.caption)
            Text(byteSize).font(.caption)
            Text(pixelSize.isEmpty ? NSLocalizedString("detail_unknown", comment: "") : pixelSize)
                .font(.caption)
            Text(MediaKind.from(path: path).rawValue).font(.caption)
            if playback.membershipNames(path: path).isEmpty {
                Text(NSLocalizedString("detail_no_lists", comment: "")).font(.caption)
            } else {
                Text(playback.membershipNames(path: path).joined(separator: ", ")).font(.caption)
            }
            HStack {
                Button(NSLocalizedString("copy_path", comment: "")) { copy(path) }
                Button(NSLocalizedString("reveal_finder", comment: "")) { reveal(path) }
                Button(NSLocalizedString("favorite_toggle", comment: "")) {
                    let wallpaper = endup_wp(id: UUID(), name: URL(fileURLWithPath: path).lastPathComponent, path: path, preview: nil, createdDate: Date(), fileSize: 0)
                    macpaperService.shared.toggleFavorite(wallpaper)
                }
                Button(NSLocalizedString("apply_current", comment: "")) {
                    _ = playback.apply(path: path, name: nil, scope: .currentDesktop, displayUUID: SpaceBinding.currentDisplayUUID(), stopRotation: true, origin: "manual", confirmedCrossDisplay: false, recordHistory: true)
                }
                Button(NSLocalizedString("done", comment: "")) { dismiss() }
            }
            Spacer()
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 240)
        .onAppear(perform: loadFacts)
    }

    private func loadFacts() {
        let url = URL(fileURLWithPath: path)
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            byteSize = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        } else {
            byteSize = NSLocalizedString("detail_unknown", comment: "")
        }
        DispatchQueue.global(qos: .utility).async {
            let text = pixelText(url)
            DispatchQueue.main.async { pixelSize = text }
        }
    }

    private func pixelText(_ url: URL) -> String {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = props[kCGImagePropertyPixelWidth] as? Int,
           let height = props[kCGImagePropertyPixelHeight] as? Int {
            return "\(width) × \(height)"
        }
        let asset = AVAsset(url: url)
        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            return "\(Int(abs(size.width))) × \(Int(abs(size.height)))"
        }
        return NSLocalizedString("detail_unknown", comment: "")
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func copy(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }
}

struct StorageSettingsSection: View {
    @ObservedObject private var playback = PlaybackCoordinator.shared
    @State private var report = StorageReport.empty
    @State private var lastCleanup = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("storage_title", comment: "")).font(.headline)
            Text(libraryText).font(.callout)
            Text(String(format: NSLocalizedString("storage_external", comment: ""), report.externalPaths.count))
                .font(.caption)
            ForEach(report.externalPaths, id: \.self) { path in
                Text(path).font(.caption).textSelection(.enabled)
            }
            Text(cacheText).font(.caption)
            Text(NSLocalizedString("storage_memory_note", comment: "")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(NSLocalizedString("storage_clear_url", comment: "")) {
                    let before = URLCache.shared.currentDiskUsage
                    URLCache.shared.removeAllCachedResponses()
                    lastCleanup = String(format: NSLocalizedString("storage_cleared", comment: ""), before, URLCache.shared.currentDiskUsage)
                    refresh()
                }
                Button(NSLocalizedString("storage_clear_memory", comment: "")) {
                    ImageCache.shared.clear()
                    ImageCache.video.clear()
                }
                Button(NSLocalizedString("storage_refresh", comment: "")) { refresh() }
            }
            if !lastCleanup.isEmpty { Text(lastCleanup).font(.caption) }
            Text(NSLocalizedString("storage_save_note", comment: "")).font(.caption).foregroundStyle(.secondary)
        }
        .onAppear(perform: refresh)
    }

    private var libraryText: String {
        if report.libraryKnown, let bytes = report.libraryBytes {
            return String(format: NSLocalizedString("storage_library", comment: ""), ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        }
        return NSLocalizedString("storage_library_unknown", comment: "")
    }

    private var cacheText: String {
        String(format: NSLocalizedString("storage_urlcache", comment: ""), ByteCountFormatter.string(fromByteCount: Int64(report.urlCacheBytes), countStyle: .file))
    }

    private func refresh() {
        report = StorageReport.make()
    }
}

struct StorageReport {
    var libraryBytes: Int64?
    var libraryKnown: Bool
    var externalPaths: [String]
    var urlCacheBytes: Int

    static let empty = StorageReport(libraryBytes: nil, libraryKnown: false, externalPaths: [], urlCacheBytes: 0)

    static func make() -> StorageReport {
        let root = MoonleafConfigStore.libraryRoot
        var facts: [FileFact] = []
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey])
                if values?.isSymbolicLink == true {
                    facts.append(FileFact(path: url.path, isSymlink: true, byteSize: nil, insideLibrary: true))
                    enumerator.skipDescendants()
                    continue
                }
                if values?.isDirectory == true { continue }
                facts.append(FileFact(path: url.path, isSymlink: false, byteSize: values?.fileSize.map(Int64.init), insideLibrary: true))
            }
        }
        let snapshot = LibraryCatalog.shared.snapshot()
        for asset in snapshot.assets where !asset.path.hasPrefix(root.path) {
            facts.append(FileFact(path: asset.path, isSymlink: false, byteSize: nil, insideLibrary: false))
        }
        let summary = StorageLogic.summarize(facts)
        return StorageReport(
            libraryBytes: summary.libraryBytes,
            libraryKnown: summary.libraryKnown,
            externalPaths: summary.externalPaths,
            urlCacheBytes: URLCache.shared.currentDiskUsage
        )
    }
}
