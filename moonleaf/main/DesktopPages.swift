//
//  DesktopPages.swift
//  moonleaf
//
//  Usage, playlists, storage and the shared asset detail. These pages read
//  the same coordinator the menu bar uses.
//

import AVFoundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

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
        case .usage: return "display"
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
        GlassPanel(cornerRadius: 20, padding: 12, useUltraThin: true, strokeOpacity: 0.1) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(AppPage.allCases) { page in
                    tabButton(
                        title: page.title,
                        icon: page.symbol,
                        isSelected: navigation.page == page,
                        fullWidth: true
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            navigation.page = page
                        }
                    }
                    .accessibilityLabel(page.title)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: 196)
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
    @State private var showDisplayPopover = false
    @State private var showSpacePopover = false
    @State private var showKindPopover = false
    @State private var historyWidth: CGFloat = 600

    @State private var confirmRandomAll = false
    var body: some View {
        VStack(spacing: 0) {
            GlassToolbar {
                PageHeader(
                    title: NSLocalizedString("page_overview_header", comment: ""),
                    subtitle: playback.separateSpaces
                        ? NSLocalizedString("spaces_separate", comment: "")
                        : NSLocalizedString("spaces_shared", comment: "")
                ) {
                    VStack(alignment: .trailing, spacing: 8) {
                        randomControl
                        displayFilterControl
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let status = playback.statusMessage {
                        InlineBanner(message: status)
                    }

                    desktopsSection
                    historySection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
        .alert(NSLocalizedString("random_confirm_title", comment: ""), isPresented: $confirmRandomAll) {
            Button(NSLocalizedString("apply_confirm", comment: "")) {
                runRandom(operableTargets.map(\.key))
            }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(randomConfirmMessage)
        }
    }

    private var operableTargets: [DesktopTarget] {
        playback.targets.filter { !playback.targetUnavailable($0.key) }
    }

    private var randomConfirmMessage: String {
        let operable = operableTargets
        let displays = Set(operable.flatMap(\.displayUUIDs)).count
        var listCount = 0
        var libraryCount = 0
        for target in operable {
            switch RandomLogic.source(
                listKind: playback.session(for: target.key)?.listKind,
                playlistID: playback.session(for: target.key)?.playlistID,
                folderPath: playback.session(for: target.key)?.folderPath,
                includeSubdirectories: playback.session(for: target.key)?.includeSubdirectories
            ) {
            case .playlist, .favorites, .folder:
                listCount += 1
            case .library:
                libraryCount += 1
            case .missing:
                break
            }
        }
        var message = String(format: NSLocalizedString("random_confirm_body", comment: ""), operable.count, displays)
        message += " "
        message += String(format: NSLocalizedString("random_confirm_sources", comment: ""), listCount, libraryCount)
        let excluded = playback.targets.count - operable.count
        if excluded > 0 {
            message += " "
            message += String(format: NSLocalizedString("random_confirm_excluded", comment: ""), excluded)
        }
        return message
    }

    private var randomControl: some View {
        PrimaryGradientButton(
            title: NSLocalizedString("random_action", comment: ""),
            icon: "shuffle",
            isDisabled: playback.applyPending || playback.targets.isEmpty
        ) {
            confirmRandomAll = true
        }
    }

    private var displayFilterControl: some View {
        Group {
            if displayChoices.count > 1 {
                ChipButton(
                    title: displayFilter.isEmpty ? NSLocalizedString("filter_all", comment: "") : displayFilter,
                    icon: "display",
                    trailingIcon: "chevron.down",
                    isActive: !displayFilter.isEmpty
                ) {
                    showDisplayPopover.toggle()
                }
                .popover(isPresented: $showDisplayPopover, arrowEdge: .bottom) {
                    displayPopoverContent
                }
            }
        }
    }

    private func runRandom(_ keys: [String]) {
        _ = playback.randomWallpaper(keys: keys)
    }

    private var desktopsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("section_desktops", comment: ""))
                .font(Font(font_loader.bold(size: 16)))
                .foregroundStyle(.primary.opacity(0.9))
                .padding(.leading, 4)

            let displayNames = grouped.keys.sorted().filter { displayFilter.isEmpty || $0 == displayFilter }
            if displayNames.isEmpty {
                GlassPanel(cornerRadius: 20, padding: 16) {
                    GlassEmptyState(
                        icon: "display",
                        title: NSLocalizedString("scope_no_current", comment: "")
                    )
                }
            } else {
                ForEach(displayNames, id: \.self) { display in
                    let targets = grouped[display] ?? []
                    GlassPanel(cornerRadius: 20, padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "display")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(MoonleafPalette.periwinkle)
                                Text(display)
                                    .font(Font(font_loader.bold(size: 16)))
                                    .foregroundStyle(.primary.opacity(0.9))
                                Spacer()
                                StatusPill(text: "\(targets.count)", muted: true)
                            }

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 270, maximum: 460), spacing: 12)],
                                spacing: 12
                            ) {
                                ForEach(targets) { target in
                                    DesktopTargetCard(
                                        target: target,
                                        onOpenDetail: { detailPath = $0 },
                                        onRequestCrossDisplay: { path, name in
                                            pendingCrossPath = path
                                            pendingCrossName = name
                                            confirmCrossDisplay = true
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("section_history", comment: ""))
                        .font(Font(font_loader.bold(size: 16)))
                        .foregroundStyle(.primary.opacity(0.9))
                    Text(String(format: NSLocalizedString("history_count", comment: ""), playback.history.count, HistoryEvent.limit))
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    ChipButton(
                        title: NSLocalizedString("history_recent", comment: ""),
                        icon: "sparkles",
                        isActive: !timeline
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) { timeline = false }
                    }
                    ChipButton(
                        title: NSLocalizedString("history_timeline", comment: ""),
                        icon: "calendar",
                        isActive: timeline
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) { timeline = true }
                    }
                }

                Menu {
                    Button {
                        playback.setHistoryEnabled(!playback.historyEnabled)
                    } label: {
                        HStack {
                            Text(NSLocalizedString("history_enabled", comment: ""))
                            if playback.historyEnabled {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Text(NSLocalizedString("history_clear", comment: ""))
                    }
                    .disabled(playback.history.isEmpty)
                } label: {
                    CircleMenuLabel()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 4)

            GlassPanel(cornerRadius: 16, padding: 12, useUltraThin: false) {
                let compactFilter = historyWidth < 680
                Color.clear
                    .frame(height: compactFilter ? 78 : 34)
                    .overlay {
                        if compactFilter {
                            VStack(alignment: .leading, spacing: 8) {
                                GlassSearchField(
                                    placeholder: NSLocalizedString("search_name", comment: ""),
                                    text: $query
                                )
                                HStack(spacing: 8) {
                                    historyDisplayChip
                                    historySpaceChip
                                    historyKindChip
                                    Spacer(minLength: 0)
                                }
                            }
                        } else {
                            HStack(spacing: 8) {
                                GlassSearchField(
                                    placeholder: NSLocalizedString("search_name", comment: ""),
                                    text: $query
                                )
                                .frame(minWidth: 140, maxWidth: 260)

                                historyDisplayChip
                                historySpaceChip
                                historyKindChip
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .background(WidthReader { width in
                        if abs(historyWidth - width) > 4 {
                            historyWidth = width
                        }
                    })
            }

            if filteredHistory.isEmpty {
                GlassPanel(cornerRadius: 20, padding: 16) {
                    GlassEmptyState(
                        icon: "clock.arrow.circlepath",
                        title: NSLocalizedString("history_empty", comment: ""),
                        subtitle: NSLocalizedString("history_empty_desc", comment: "")
                    )
                }
            } else if timeline {
                ForEach(HistoryLogic.timeline(filteredHistory), id: \.day) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.day.formatted(date: .abbreviated, time: .omitted))
                            .font(Font(font_loader.bold(size: 14)))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                            .padding(.top, 4)
                        ForEach(group.events) { event in
                            HistoryRowView(
                                event: event,
                                targetSummary: targetSummary(event.targetKeys),
                                resolvedPath: playback.resolvedPath(assetID: event.assetID),
                                onOpenDetail: { detailPath = $0 }
                            )
                        }
                    }
                }
            } else {
                ForEach(HistoryLogic.deduped(filteredHistory), id: \.assetID) { row in
                    HistoryRowView(
                        event: row.latest,
                        targetSummary: targetSummary(row.latest.targetKeys),
                        resolvedPath: playback.resolvedPath(assetID: row.latest.assetID),
                        onOpenDetail: { detailPath = $0 }
                    )
                }
            }
        }
    }

    private var displayPopoverContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            PopoverMenuItem(
                title: NSLocalizedString("filter_all", comment: ""),
                isSelected: displayFilter.isEmpty
            ) {
                displayFilter = ""
                showDisplayPopover = false
            }
            ForEach(displayChoices, id: \.self) { name in
                PopoverMenuItem(title: name, isSelected: displayFilter == name) {
                    displayFilter = name
                    showDisplayPopover = false
                }
            }
        }
        .padding(8)
        .frame(width: 200)
    }

    private var spacePopoverContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            PopoverMenuItem(
                title: NSLocalizedString("filter_all", comment: ""),
                isSelected: spaceFilter.isEmpty
            ) {
                spaceFilter = ""
                showSpacePopover = false
            }
            ForEach(playback.targets) { target in
                let label = "\(target.displayName) · " + String(format: NSLocalizedString("desktop_n", comment: ""), target.spaceIndex)
                PopoverMenuItem(title: label, isSelected: spaceFilter == target.key) {
                    spaceFilter = target.key
                    showSpacePopover = false
                }
            }
        }
        .padding(8)
        .frame(width: 240)
    }

    private var kindPopoverContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            PopoverMenuItem(title: NSLocalizedString("filter_all", comment: ""), isSelected: kindFilter == "all") {
                kindFilter = "all"
                showKindPopover = false
            }
            PopoverMenuItem(title: NSLocalizedString("kind_still", comment: ""), isSelected: kindFilter == "still") {
                kindFilter = "still"
                showKindPopover = false
            }
            PopoverMenuItem(title: NSLocalizedString("kind_video", comment: ""), isSelected: kindFilter == "video") {
                kindFilter = "video"
                showKindPopover = false
            }
            PopoverMenuItem(title: "GIF", isSelected: kindFilter == "gif") {
                kindFilter = "gif"
                showKindPopover = false
            }
        }
        .padding(8)
        .frame(width: 160)
    }

    private var selectedSpaceTitle: String {
        guard !spaceFilter.isEmpty,
              let target = playback.targets.first(where: { $0.key == spaceFilter }) else {
            return NSLocalizedString("filter_desktop", comment: "")
        }
        return String(format: NSLocalizedString("desktop_n", comment: ""), target.spaceIndex)
    }

    private var selectedKindTitle: String {
        switch kindFilter {
        case "still": return NSLocalizedString("kind_still", comment: "")
        case "video": return NSLocalizedString("kind_video", comment: "")
        case "gif": return "GIF"
        default: return NSLocalizedString("filter_kind", comment: "")
        }
    }
    private var historyDisplayChip: some View {
        ChipButton(
            title: displayFilter.isEmpty ? NSLocalizedString("filter_display", comment: "") : displayFilter,
            icon: "display",
            trailingIcon: "chevron.down",
            isActive: !displayFilter.isEmpty
        ) {
            showDisplayPopover.toggle()
        }
        .fixedSize()
        .popover(isPresented: $showDisplayPopover, arrowEdge: .bottom) {
            displayPopoverContent
        }
    }

    private var historySpaceChip: some View {
        ChipButton(
            title: selectedSpaceTitle,
            icon: "macwindow",
            trailingIcon: "chevron.down",
            isActive: !spaceFilter.isEmpty
        ) {
            showSpacePopover.toggle()
        }
        .fixedSize()
        .popover(isPresented: $showSpacePopover, arrowEdge: .bottom) {
            spacePopoverContent
        }
    }

    private var historyKindChip: some View {
        ChipButton(
            title: selectedKindTitle,
            icon: "line.3.horizontal.decrease.circle",
            trailingIcon: "chevron.down",
            isActive: kindFilter != "all"
        ) {
            showKindPopover.toggle()
        }
        .fixedSize()
        .popover(isPresented: $showKindPopover, arrowEdge: .bottom) {
            kindPopoverContent
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

    private func targetSummary(_ keys: [String]) -> String {
        keys.map { key in
            if let target = playback.targets.first(where: { $0.key == key }) {
                return "\(target.displayName) · " + String(format: NSLocalizedString("desktop_n", comment: ""), target.spaceIndex)
            }
            return NSLocalizedString("target_unavailable", comment: "")
        }.joined(separator: ", ")
    }
}

private struct DesktopTargetCard: View {
    let target: DesktopTarget
    let onOpenDetail: (String) -> Void
    let onRequestCrossDisplay: (String, String?) -> Void

    @ObservedObject private var playback = PlaybackCoordinator.shared
    @ObservedObject private var service = macpaperService.shared

    var body: some View {
        let session = playback.session(for: target.key)
        let unavailable = playback.targetUnavailable(target.key)
        let isPaused = session?.paused == true
        let statusText = playback.playbackDescription(for: target.key)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                MediaThumb(
                    path: session?.path,
                    size: CGSize(width: 96, height: 64),
                    cornerRadius: 12
                )
                .onTapGesture {
                    if let path = session?.path {
                        onOpenDetail(path)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(String(format: NSLocalizedString("desktop_n", comment: ""), target.spaceIndex))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary.opacity(0.92))

                        if target.isCurrent {
                            StatusPill(
                                text: NSLocalizedString("desktop_current", comment: ""),
                                tint: MoonleafPalette.periwinkle
                            )
                        }

                        if unavailable {
                            StatusPill(
                                text: NSLocalizedString("target_unavailable", comment: ""),
                                icon: "exclamationmark.triangle.fill",
                                tint: MoonleafPalette.amber
                            )
                        }
                    }

                    Text(session?.assetName ?? NSLocalizedString("desktop_unset", comment: ""))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(session == nil ? Color.secondary : Color.primary.opacity(0.88))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        StatusPill(
                            text: statusText,
                            icon: statusIcon(unavailable: unavailable, isPaused: isPaused, session: session),
                            tint: statusTint(unavailable: unavailable, isPaused: isPaused, session: session),
                            muted: session == nil && !unavailable
                        )

                        if let pid = session?.playlistID,
                           let listName = playback.playlists.first(where: { $0.id == pid })?.name,
                           !listName.isEmpty {
                            StatusPill(
                                text: listName,
                                icon: "list.bullet",
                                tint: MoonleafPalette.periwinkle
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                CircleIconButton(
                    icon: "shuffle",
                    style: .playback,
                    isDisabled: unavailable || playback.applyPending,
                    helpText: NSLocalizedString("random_card", comment: ""),
                    accessibilityLabelText: NSLocalizedString("random_card", comment: "")
                ) {
                    _ = playback.randomWallpaper(keys: [target.key])
                }

                CircleIconButton(
                    icon: isPaused ? "play.fill" : "pause.fill",
                    style: .playback,
                    isDisabled: unavailable || session == nil,
                    helpText: isPaused ? NSLocalizedString("pause_resume", comment: "") : NSLocalizedString("pause_toggle", comment: "")
                ) {
                    playback.setPaused(!isPaused, targetKey: target.key)
                }

                CircleIconButton(
                    icon: "forward.end.fill",
                    style: .playback,
                    isDisabled: unavailable || session == nil,
                    helpText: NSLocalizedString("next_item", comment: "")
                ) {
                    playback.next(targetKey: target.key)
                }

                CircleIconButton(
                    icon: "info.circle",
                    style: .neutral,
                    isDisabled: session?.path == nil,
                    helpText: NSLocalizedString("detail_open", comment: "")
                ) {
                    if let path = session?.path {
                        onOpenDetail(path)
                    }
                }

                CircleIconButton(
                    icon: "folder",
                    style: .finder,
                    isDisabled: session?.path == nil,
                    helpText: NSLocalizedString("reveal_finder", comment: "")
                ) {
                    if let path = session?.path {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                }
                Spacer()

                Menu {
                    if let path = session?.path {
                        let wp = endup_wp(
                            id: UUID(),
                            name: session?.assetName ?? URL(fileURLWithPath: path).lastPathComponent,
                            path: path,
                            preview: nil,
                            createdDate: Date(),
                            fileSize: 0
                        )
                        Button(service.isFavorite(wp) ? NSLocalizedString("unfavorite_toggle", comment: "") : NSLocalizedString("favorite_toggle", comment: "")) {
                            service.toggleFavorite(wp)
                        }

                        if !playback.playlists.isEmpty {
                            Menu(NSLocalizedString("browse_add_to_playlist", comment: "")) {
                                ForEach(playback.playlists) { list in
                                    Button(list.name) {
                                        playback.addToPlaylist(paths: [path], playlistID: list.id)
                                    }
                                }
                            }
                        }

                        if let displayUUID = target.displayUUIDs.first {
                            Button(NSLocalizedString("apply_display", comment: "")) {
                                _ = playback.apply(
                                    path: path,
                                    name: session?.assetName,
                                    scope: .displayDesktops,
                                    displayUUID: displayUUID,
                                    stopRotation: true,
                                    origin: "manual",
                                    confirmedCrossDisplay: false,
                                    recordHistory: true
                                )
                            }
                        }

                        if playback.targets.count > 1 {
                            Button(NSLocalizedString("apply_all_displays", comment: "")) {
                                onRequestCrossDisplay(path, session?.assetName)
                            }
                        }

                        Button(NSLocalizedString("copy_path", comment: "")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(path, forType: .string)
                        }
                        Divider()
                    }
                    if session != nil {
                        Button(NSLocalizedString("unset_current", comment: ""), role: .destructive) {
                            playback.clearTarget(target.key)
                        }
                    }
                } label: {
                    CircleMenuLabel()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(session == nil)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.32))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            target.isCurrent ? MoonleafPalette.periwinkle.opacity(0.45) : Color.primary.opacity(0.1),
                            lineWidth: target.isCurrent ? 1.5 : 0.8
                        )
                }
        }
    }

    private func statusIcon(unavailable: Bool, isPaused: Bool, session: TargetSession?) -> String? {
        if unavailable { return "exclamationmark.triangle.fill" }
        if session == nil { return nil }
        if isPaused { return "pause.fill" }
        return "play.fill"
    }

    private func statusTint(unavailable: Bool, isPaused: Bool, session: TargetSession?) -> Color {
        if unavailable || isPaused { return MoonleafPalette.amber }
        if session == nil { return .secondary }
        return MoonleafPalette.mint
    }
}

private struct HistoryRowView: View {
    let event: HistoryEvent
    let targetSummary: String
    let resolvedPath: String?
    let onOpenDetail: (String) -> Void

    @ObservedObject private var playback = PlaybackCoordinator.shared
    @ObservedObject private var service = macpaperService.shared
    @State private var isHovered = false

    private var fileExists: Bool {
        guard let resolvedPath else { return false }
        return FileManager.default.fileExists(atPath: resolvedPath)
    }

    var body: some View {
        HStack(spacing: 12) {
            MediaThumb(
                path: resolvedPath,
                size: CGSize(width: 60, height: 40),
                cornerRadius: 8
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(event.assetName)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(fileExists ? Color.primary.opacity(0.92) : Color.secondary)
                        .lineLimit(1)

                    if !fileExists {
                        StatusPill(
                            text: NSLocalizedString("asset_missing", comment: ""),
                            icon: "exclamationmark.triangle",
                            tint: MoonleafPalette.amber
                        )
                    }
                }

                HStack(spacing: 6) {
                    Text(event.appliedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text(targetSummary)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    StatusPill(
                        text: event.origin == "automatic"
                            ? NSLocalizedString("origin_auto", comment: "")
                            : NSLocalizedString("origin_manual", comment: ""),
                        muted: event.origin != "automatic"
                    )
                    if let list = event.playlistName, !list.isEmpty {
                        StatusPill(
                            text: list,
                            icon: "list.bullet",
                            tint: MoonleafPalette.periwinkle
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                let canAct = resolvedPath != nil && fileExists
                CircleIconButton(
                    icon: "wand.and.stars",
                    style: .playback,
                    isDisabled: !canAct,
                    helpText: NSLocalizedString("apply_current_keep_rotation", comment: "")
                ) {
                    if let path = resolvedPath, fileExists {
                        _ = playback.apply(
                            path: path,
                            name: event.assetName,
                            scope: .currentDesktop,
                            displayUUID: SpaceBinding.currentDisplayUUID(),
                            stopRotation: false,
                            origin: "manual",
                            confirmedCrossDisplay: false,
                            recordHistory: true
                        )
                    }
                }
                .opacity(isHovered && canAct ? 1 : 0)
                .allowsHitTesting(isHovered && canAct)

                CircleIconButton(
                    icon: "info.circle",
                    style: .neutral,
                    isDisabled: !canAct,
                    helpText: NSLocalizedString("detail_open", comment: "")
                ) {
                    if let path = resolvedPath, fileExists {
                        onOpenDetail(path)
                    }
                }
                .opacity(isHovered && canAct ? 1 : 0)
                .allowsHitTesting(isHovered && canAct)

                Menu {
                    if let path = resolvedPath, fileExists {
                        Button(NSLocalizedString("apply_current_keep_rotation", comment: "")) {
                            _ = playback.apply(
                                path: path,
                                name: event.assetName,
                                scope: .currentDesktop,
                                displayUUID: SpaceBinding.currentDisplayUUID(),
                                stopRotation: false,
                                origin: "manual",
                                confirmedCrossDisplay: false,
                                recordHistory: true
                            )
                        }
                        Button(NSLocalizedString("apply_current_stop_rotation", comment: "")) {
                            _ = playback.apply(
                                path: path,
                                name: event.assetName,
                                scope: .currentDesktop,
                                displayUUID: SpaceBinding.currentDisplayUUID(),
                                stopRotation: true,
                                origin: "manual",
                                confirmedCrossDisplay: false,
                                recordHistory: true
                            )
                        }
                        Divider()
                        Button(NSLocalizedString("detail_open", comment: "")) {
                            onOpenDetail(path)
                        }
                        let wp = endup_wp(
                            id: UUID(),
                            name: event.assetName,
                            path: path,
                            preview: nil,
                            createdDate: Date(),
                            fileSize: 0
                        )
                        Button(service.isFavorite(wp) ? NSLocalizedString("unfavorite_toggle", comment: "") : NSLocalizedString("favorite_toggle", comment: "")) {
                            service.toggleFavorite(wp)
                        }
                        if !playback.playlists.isEmpty {
                            Menu(NSLocalizedString("browse_add_to_playlist", comment: "")) {
                                ForEach(playback.playlists) { list in
                                    Button(list.name) {
                                        playback.addToPlaylist(paths: [path], playlistID: list.id)
                                    }
                                }
                            }
                        }
                        Button(NSLocalizedString("reveal_finder", comment: "")) {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                        Button(NSLocalizedString("copy_path", comment: "")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(path, forType: .string)
                        }
                        Divider()
                    }
                    Button(NSLocalizedString("history_remove", comment: ""), role: .destructive) {
                        playback.removeHistory(event.id)
                    }
                } label: {
                    CircleMenuLabel()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(isHovered ? 0.22 : 0.34))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(isHovered ? 0.20 : 0.10), lineWidth: 0.8)
                }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
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
    @State private var assignError: String?
    @State private var showOrderPopover = false
    @State private var showIntervalPopover = false
    @State private var showTargetPopover = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var draggingAssetID: UUID?
    @State private var detailPath: String?
    @State private var pageWidth: CGFloat = 600
    @State private var showPlaylistPickerPopover = false

    var body: some View {
        let compactLayout = pageWidth < 680
        Group {
            if compactLayout {
                VStack(alignment: .leading, spacing: 12) {
                    compactSelectorBar
                    detailOrEmpty
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    sidebarColumn
                    detailOrEmpty
                }
            }
        }
        .background(WidthReader { width in
            if abs(pageWidth - width) > 4 {
                pageWidth = width
            }
        })
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .onAppear {
            if selectedID == nil {
                selectedID = playback.playlists.first?.id
            }
        }
        .onChange(of: selectedID) { _ in
            assignError = nil
            isRenaming = false
        }
        .sheet(item: detailBinding) { item in
            AssetDetailSheet(path: item.path)
        }
        .alert(NSLocalizedString("playlist_delete_title", comment: ""), isPresented: $confirmDelete) {
            Button(NSLocalizedString("playlist_delete", comment: ""), role: .destructive) {
                if let id = selectedID {
                    playback.deletePlaylist(id)
                    selectedID = playback.playlists.first?.id
                }
            }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("playlist_delete_message", comment: ""))
        }
    }

    @ViewBuilder
    private var detailOrEmpty: some View {
        if let list = playback.playlists.first(where: { $0.id == selectedID }) {
            playlistDetail(list)
        } else {
            GlassPanel(cornerRadius: 20, padding: 20) {
                GlassEmptyState(
                    icon: "music.note.list",
                    title: playback.playlists.isEmpty
                        ? NSLocalizedString("playlists_empty", comment: "")
                        : NSLocalizedString("playlist_pick", comment: ""),
                    subtitle: playback.playlists.isEmpty
                        ? NSLocalizedString("playlists_empty_desc", comment: "")
                        : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var compactSelectorBar: some View {
        GlassPanel(cornerRadius: 16, padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    let currentList = playback.playlists.first(where: { $0.id == selectedID })
                    ChipButton(
                        title: currentList?.name ?? NSLocalizedString("playlist_pick", comment: ""),
                        icon: "music.note.list",
                        trailingIcon: "chevron.down",
                        isActive: currentList != nil,
                        isDisabled: playback.playlists.isEmpty
                    ) {
                        showPlaylistPickerPopover.toggle()
                    }
                    .popover(isPresented: $showPlaylistPickerPopover, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(playback.playlists) { list in
                                PopoverMenuItem(
                                    title: list.name,
                                    subtitle: "\(list.assetIDs.count)",
                                    isSelected: selectedID == list.id
                                ) {
                                    selectedID = list.id
                                    showPlaylistPickerPopover = false
                                }
                            }
                        }
                        .padding(8)
                        .frame(width: 220)
                    }

                    TextField(NSLocalizedString("playlist_name", comment: ""), text: $newName)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.regularMaterial.opacity(0.8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                }
                        }
                        .onSubmit(createCurrentPlaylist)

                    PrimaryGradientButton(
                        title: NSLocalizedString("playlist_create", comment: ""),
                        icon: "plus",
                        isDisabled: newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        action: createCurrentPlaylist
                    )

                    if let id = selectedID, playback.playlists.contains(where: { $0.id == id }) {
                        CircleIconButton(
                            icon: "trash",
                            style: .delete,
                            helpText: NSLocalizedString("playlist_delete", comment: "")
                        ) {
                            confirmDelete = true
                        }
                    }
                }
            }
        }
    }
    private var detailBinding: Binding<PathItem?> {
        Binding(
            get: { detailPath.map(PathItem.init) },
            set: { detailPath = $0?.path }
        )
    }

    private var sidebarColumn: some View {
        GlassPanel(cornerRadius: 20, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField(NSLocalizedString("playlist_name", comment: ""), text: $newName)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.regularMaterial.opacity(0.8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                }
                        }
                        .onSubmit(createCurrentPlaylist)

                    PrimaryGradientButton(
                        title: NSLocalizedString("playlist_create", comment: ""),
                        icon: "plus",
                        isDisabled: newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        action: createCurrentPlaylist
                    )
                }

                if playback.playlists.isEmpty {
                    GlassEmptyState(
                        icon: "list.bullet",
                        title: NSLocalizedString("playlist_none", comment: "")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(playback.playlists) { list in
                                PlaylistSidebarRow(
                                    list: list,
                                    coverPath: firstAvailablePath(in: list),
                                    isSelected: selectedID == list.id
                                ) {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedID = list.id
                                    }
                                }
                            }
                        }
                    }
                }

                if let id = selectedID, playback.playlists.contains(where: { $0.id == id }) {
                    ChipButton(
                        title: NSLocalizedString("playlist_delete", comment: ""),
                        icon: "trash",
                        tint: MoonleafPalette.rose
                    ) {
                        confirmDelete = true
                    }
                }
            }
        }
        .frame(width: 244)
    }

    private func createCurrentPlaylist() {
        if let id = playback.createPlaylist(name: newName) {
            selectedID = id
            newName = ""
        }
    }

    private func firstAvailablePath(in list: NamedPlaylist) -> String? {
        for assetID in list.assetIDs {
            if let path = playback.resolvedPath(assetID: assetID),
               FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func playlistDetail(_ list: NamedPlaylist) -> some View {
        let available = list.assetIDs.compactMap { playback.resolvedPath(assetID: $0) }
            .filter { FileManager.default.fileExists(atPath: $0) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GlassPanel(cornerRadius: 20, padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            MediaThumb(
                                path: available.first,
                                size: CGSize(width: 84, height: 56),
                                cornerRadius: 12
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                if isRenaming {
                                    HStack(spacing: 6) {
                                        TextField("", text: $renameText)
                                            .textFieldStyle(PlainTextFieldStyle())
                                            .font(Font(font_loader.bold(size: 20)))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08)))
                                            .onSubmit { commitRename(list) }
                                        CircleIconButton(icon: "checkmark", size: 26, style: .success, helpText: NSLocalizedString("done", comment: "")) {
                                            commitRename(list)
                                        }
                                        CircleIconButton(icon: "xmark", size: 26, style: .neutral, helpText: NSLocalizedString("cancel", comment: "")) {
                                            isRenaming = false
                                        }
                                    }
                                } else {
                                    HStack(spacing: 8) {
                                        Text(list.name)
                                            .font(Font(font_loader.bold(size: 22)))
                                            .foregroundStyle(.primary.opacity(0.92))
                                            .lineLimit(1)
                                        CircleIconButton(icon: "pencil", size: 26, style: .edit, helpText: NSLocalizedString("library_rename", comment: "")) {
                                            renameText = list.name
                                            isRenaming = true
                                        }
                                    }
                                }

                                Text(String(format: NSLocalizedString("playlist_available", comment: ""), available.count, list.assetIDs.count))
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        let orderChip = ChipButton(
                            title: list.order == "random"
                                ? NSLocalizedString("order_random", comment: "")
                                : NSLocalizedString("order_sequential", comment: ""),
                            icon: list.order == "random" ? "shuffle" : "arrow.right",
                            trailingIcon: "chevron.down"
                        ) {
                            showOrderPopover.toggle()
                        }
                        .popover(isPresented: $showOrderPopover, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 4) {
                                PopoverMenuItem(
                                    title: NSLocalizedString("order_sequential", comment: ""),
                                    icon: "arrow.right",
                                    isSelected: list.order != "random"
                                ) {
                                    playback.updatePlaylistSettings(list.id, order: "sequential", interval: list.interval)
                                    showOrderPopover = false
                                }
                                PopoverMenuItem(
                                    title: NSLocalizedString("order_random", comment: ""),
                                    icon: "shuffle",
                                    isSelected: list.order == "random"
                                ) {
                                    playback.updatePlaylistSettings(list.id, order: "random", interval: list.interval)
                                    showOrderPopover = false
                                }
                            }
                            .padding(8)
                            .frame(width: 170)
                        }

                        let currentInterval = macpaperService.ShuffleInterval(rawValue: list.interval)?.displayName
                            ?? macpaperService.ShuffleInterval.oneHour.displayName
                        let intervalChip = ChipButton(
                            title: currentInterval,
                            icon: "timer",
                            trailingIcon: "chevron.down"
                        ) {
                            showIntervalPopover.toggle()
                        }
                        .popover(isPresented: $showIntervalPopover, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(macpaperService.ShuffleInterval.allCases, id: \.rawValue) { interval in
                                    PopoverMenuItem(
                                        title: interval.displayName,
                                        isSelected: list.interval == interval.rawValue
                                    ) {
                                        playback.updatePlaylistSettings(list.id, order: list.order, interval: interval.rawValue)
                                        showIntervalPopover = false
                                    }
                                }
                            }
                            .padding(8)
                            .frame(width: 170)
                        }

                        let assignBtn = PrimaryGradientButton(
                            title: NSLocalizedString("playlist_assign", comment: ""),
                            icon: "desktopcomputer",
                            trailingIcon: "chevron.down",
                            isDisabled: playback.targets.isEmpty
                        ) {
                            showTargetPopover.toggle()
                        }
                        .popover(isPresented: $showTargetPopover, arrowEdge: .bottom) {
                            targetPopover(for: list)
                        }

                        if pageWidth < 680 {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    orderChip
                                    intervalChip
                                    Spacer(minLength: 0)
                                }
                                assignBtn
                            }
                        } else {
                            HStack(spacing: 8) {
                                orderChip
                                intervalChip
                                Spacer(minLength: 8)
                                assignBtn
                            }
                        }
                        if let assignError {
                            InlineBanner(message: assignError) {
                                self.assignError = nil
                            }
                        }
                    }
                }

                if list.assetIDs.isEmpty {
                    GlassPanel(cornerRadius: 20, padding: 20) {
                        GlassEmptyState(
                            icon: "photo.stack",
                            title: NSLocalizedString("list_empty", comment: ""),
                            subtitle: NSLocalizedString("playlist_empty_items_desc", comment: "")
                        )
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(list.assetIDs.enumerated()), id: \.element) { index, assetID in
                            let path = playback.resolvedPath(assetID: assetID)
                            PlaylistItemRow(
                                index: index,
                                totalCount: list.assetIDs.count,
                                assetID: assetID,
                                path: path,
                                onOpenDetail: { detailPath = $0 },
                                onMoveUp: {
                                    playback.moveInPlaylist(playlistID: list.id, from: index, to: max(0, index - 1))
                                },
                                onMoveDown: {
                                    playback.moveInPlaylist(playlistID: list.id, from: index, to: min(list.assetIDs.count - 1, index + 1))
                                },
                                onRemove: {
                                    playback.removeFromPlaylist(assetID: assetID, playlistID: list.id)
                                }
                            )
                            .onDrag {
                                draggingAssetID = assetID
                                return NSItemProvider(object: assetID.uuidString as NSString)
                            }
                            .onDrop(
                                of: [UTType.plainText],
                                delegate: PlaylistDropDelegate(
                                    destinationID: assetID,
                                    list: list,
                                    draggingAssetID: $draggingAssetID,
                                    playback: playback
                                )
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func commitRename(_ list: NamedPlaylist) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            playback.renamePlaylist(list.id, name: trimmed)
        }
        isRenaming = false
    }

    private func targetPopover(for list: NamedPlaylist) -> some View {
        let grouped = Dictionary(grouping: playback.targets, by: \.displayName)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(grouped.keys.sorted(), id: \.self) { display in
                VStack(alignment: .leading, spacing: 4) {
                    Text(display)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                    ForEach(grouped[display] ?? []) { target in
                        let unavailable = playback.targetUnavailable(target.key)
                        let activeHere = playback.session(for: target.key)?.playlistID == list.id
                        let label = String(format: NSLocalizedString("desktop_n", comment: ""), target.spaceIndex)
                            + (target.isCurrent ? " · \(NSLocalizedString("desktop_current", comment: ""))" : "")
                        PopoverMenuItem(
                            title: label,
                            icon: target.isCurrent ? "sparkles" : "macwindow",
                            isSelected: activeHere,
                            isDisabled: unavailable
                        ) {
                            showTargetPopover = false
                            if playback.assignList(playlistID: list.id, targetKey: target.key) {
                                assignError = nil
                            } else {
                                assignError = playback.statusMessage ?? NSLocalizedString("apply_none", comment: "")
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(width: 240)
    }
}

private struct PlaylistSidebarRow: View {
    let list: NamedPlaylist
    let coverPath: String?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                MediaThumb(
                    path: coverPath,
                    size: CGSize(width: 44, height: 30),
                    cornerRadius: 6,
                    showVideoBadge: false
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name)
                        .font(Font(isSelected ? font_loader.bold(size: 13) : font_loader.regular(size: 13)))
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.85))
                        .lineLimit(1)
                    Text("\(list.assetIDs.count)")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(MoonleafPalette.periwinkle.opacity(0.14))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(MoonleafPalette.periwinkle.opacity(0.4), lineWidth: 1)
                        }
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.quaternary.opacity(0.3))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}

private struct PlaylistItemRow: View {
    let index: Int
    let totalCount: Int
    let assetID: UUID
    let path: String?
    let onOpenDetail: (String) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    private var fileExists: Bool {
        guard let path else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    private var displayName: String {
        guard let path else { return NSLocalizedString("asset_missing", comment: "") }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    private var fileMeta: String {
        guard let path, fileExists else { return "" }
        let ext = (path as NSString).pathExtension.uppercased()
        if let size = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]).fileSize {
            return "\(ext) · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))"
        }
        return ext
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.7))

            MediaThumb(
                path: path,
                size: CGSize(width: 60, height: 40),
                cornerRadius: 8
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(fileExists ? Color.primary.opacity(0.92) : Color.secondary)
                        .lineLimit(1)

                    if !fileExists {
                        StatusPill(
                            text: NSLocalizedString("asset_missing", comment: ""),
                            icon: "exclamationmark.triangle",
                            tint: MoonleafPalette.amber
                        )
                    }
                }

                if !fileMeta.isEmpty {
                    Text(fileMeta)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                CircleIconButton(
                    icon: "minus.circle",
                    style: .removeList,
                    helpText: NSLocalizedString("playlist_remove_item", comment: ""),
                    action: onRemove
                )
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)

                Menu {
                    Button(NSLocalizedString("playlist_up", comment: ""), action: onMoveUp)
                        .disabled(index == 0)
                    Button(NSLocalizedString("playlist_down", comment: ""), action: onMoveDown)
                        .disabled(index >= totalCount - 1)
                    if let path, fileExists {
                        Divider()
                        Button(NSLocalizedString("detail_open", comment: "")) { onOpenDetail(path) }
                        Button(NSLocalizedString("reveal_finder", comment: "")) {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                    }
                    Divider()
                    Button(NSLocalizedString("playlist_remove_item", comment: ""), role: .destructive, action: onRemove)
                } label: {
                    CircleMenuLabel()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(isHovered ? 0.22 : 0.34))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.primary.opacity(isHovered ? 0.20 : 0.10), lineWidth: 0.8)
                }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
        .contextMenu {
            Button(NSLocalizedString("playlist_up", comment: ""), action: onMoveUp)
                .disabled(index == 0)
            Button(NSLocalizedString("playlist_down", comment: ""), action: onMoveDown)
                .disabled(index >= totalCount - 1)
            if let path, fileExists {
                Divider()
                Button(NSLocalizedString("detail_open", comment: "")) { onOpenDetail(path) }
                Button(NSLocalizedString("reveal_finder", comment: "")) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
            Divider()
            Button(NSLocalizedString("playlist_remove_item", comment: ""), role: .destructive, action: onRemove)
        }
    }
}

private struct PlaylistDropDelegate: DropDelegate {
    let destinationID: UUID
    let list: NamedPlaylist
    @Binding var draggingAssetID: UUID?
    let playback: PlaybackCoordinator

    func performDrop(info: DropInfo) -> Bool {
        draggingAssetID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID = draggingAssetID,
              draggingID != destinationID,
              let fromIndex = list.assetIDs.firstIndex(of: draggingID),
              let toIndex = list.assetIDs.firstIndex(of: destinationID) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            playback.moveInPlaylist(playlistID: list.id, from: fromIndex, to: toIndex)
        }
    }
}
private final class DetailPreviewHost {
    static let shared = DetailPreviewHost()
    private var window: NSWindow?

    func show(path: String, title: String, detail: String?) {
        close()
        let target = PreviewTarget(url: URL(fileURLWithPath: path), title: title, detail: detail)
        let host = NSHostingView(rootView: QuickPreviewOverlay(target: target, onClose: { DetailPreviewHost.shared.close() }))
        let parent = NSApp.keyWindow ?? NSApp.mainWindow
        let frame = parent?.frame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = host
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}

struct AssetDetailSheet: View {
    let path: String
    @ObservedObject private var playback = PlaybackCoordinator.shared
    @ObservedObject private var service = macpaperService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var pixelSize = ""
    @State private var byteSize = ""
    @State private var copiedImage = false
    @State private var imageHovered = false

    private var fileExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private var assetRecord: AssetRecord? {
        playback.assetRecord(path: path)
    }

    private var titleText: String {
        assetRecord?.name ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    private var wallpaperModel: endup_wp {
        endup_wp(
            id: assetRecord?.id ?? UUID(),
            name: URL(fileURLWithPath: path).lastPathComponent,
            path: path,
            preview: nil,
            createdDate: assetRecord?.addedAt ?? Date(),
            fileSize: 0
        )
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text(titleText)
                        .font(Font(font_loader.bold(size: 18)))
                        .foregroundStyle(.primary.opacity(0.92))
                        .lineLimit(1)

                    if !fileExists {
                        StatusPill(
                            text: NSLocalizedString("asset_missing", comment: ""),
                            icon: "exclamationmark.triangle",
                            tint: MoonleafPalette.amber
                        )
                    }

                    Spacer()

                    FavoriteButton(
                        isFavorite: service.isFavorite(wallpaperModel),
                        action: { service.toggleFavorite(wallpaperModel) }
                    )

                    CircleIconButton(
                        icon: "xmark",
                        size: 30,
                        style: .neutral,
                        helpText: NSLocalizedString("done", comment: "")
                    ) {
                        dismiss()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ZStack(alignment: .topTrailing) {
                            MediaThumb(
                                path: path,
                                size: CGSize(width: 440, height: 176),
                                cornerRadius: 16
                            )
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                openPreview()
                            }

                            if imageHovered && fileExists {
                                CircleIconButton(
                                    icon: "eye",
                                    size: 32,
                                    style: .darkFrosted,
                                    helpText: NSLocalizedString("preview_open", comment: ""),
                                    accessibilityLabelText: NSLocalizedString("preview_open", comment: "")
                                ) {
                                    openPreview()
                                }
                                .padding(10)
                            }
                        }
                        .onHover { hovering in
                            withAnimation(.easeOut(duration: 0.15)) {
                                imageHovered = hovering
                            }
                        }

                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                            spacing: 10
                        ) {
                            factCell(
                                label: NSLocalizedString("asset_details_format", comment: ""),
                                value: formatDisplay
                            )
                            factCell(
                                label: NSLocalizedString("asset_details_resolution", comment: ""),
                                value: pixelSize.isEmpty ? NSLocalizedString("detail_unknown", comment: "") : pixelSize
                            )
                            factCell(
                                label: NSLocalizedString("asset_details_size", comment: ""),
                                value: byteSize.isEmpty ? NSLocalizedString("detail_unknown", comment: "") : byteSize
                            )
                            factCell(
                                label: NSLocalizedString("asset_details_source", comment: ""),
                                value: sourceDisplay
                            )
                            factCell(
                                label: NSLocalizedString("asset_details_location", comment: ""),
                                value: locationDisplay
                            )
                        }

                        HStack(spacing: 8) {
                            Text(path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            CircleIconButton(
                                icon: copiedImage ? "checkmark" : "photo",
                                size: 28,
                                style: copiedImage ? .success : .neutral,
                                isDisabled: !fileExists,
                                helpText: NSLocalizedString("copy_image", comment: ""),
                                accessibilityLabelText: NSLocalizedString("copy_image", comment: "")
                            ) {
                                copyImage(path)
                                copiedImage = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedImage = false }
                            }

                            CircleIconButton(
                                icon: "folder",
                                size: 28,
                                style: .finder,
                                isDisabled: !fileExists,
                                helpText: NSLocalizedString("reveal_finder", comment: "")
                            ) {
                                reveal(path)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.regularMaterial)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.28))
                                }
                                .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1), lineWidth: 0.8) }
                        }

                        let lists = playback.membershipNames(path: path)
                        HStack(spacing: 6) {
                            if lists.isEmpty {
                                Text(NSLocalizedString("detail_no_lists", comment: ""))
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(.secondary)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(lists, id: \.self) { name in
                                            StatusPill(text: name, icon: "list.bullet", tint: MoonleafPalette.periwinkle)
                                        }
                                    }
                                }
                            }

                            Spacer(minLength: 4)

                            if !playback.playlists.isEmpty && fileExists {
                                Menu {
                                    ForEach(playback.playlists) { list in
                                        Button(list.name) {
                                            playback.addToPlaylist(paths: [path], playlistID: list.id)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text(NSLocalizedString("browse_add_to_playlist", comment: ""))
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background {
                                        RoundedRectangle(cornerRadius: 9)
                                            .fill(.regularMaterial.opacity(0.8))
                                            .overlay { RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.12), lineWidth: 0.8) }
                                    }
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 4)
                }

                HStack(spacing: 10) {
                    PrimaryGradientButton(
                        title: NSLocalizedString("apply_current", comment: ""),
                        icon: "wand.and.stars",
                        isDisabled: !fileExists
                    ) {
                        _ = playback.apply(
                            path: path,
                            name: nil,
                            scope: .currentDesktop,
                            displayUUID: SpaceBinding.currentDisplayUUID(),
                            stopRotation: true,
                            origin: "manual",
                            confirmedCrossDisplay: false,
                            recordHistory: true
                        )
                    }

                    if let displayUUID = SpaceBinding.currentDisplayUUID() {
                        ChipButton(
                            title: NSLocalizedString("apply_display", comment: ""),
                            icon: "display",
                            isDisabled: !fileExists
                        ) {
                            _ = playback.apply(
                                path: path,
                                name: nil,
                                scope: .displayDesktops,
                                displayUUID: displayUUID,
                                stopRotation: true,
                                origin: "manual",
                                confirmedCrossDisplay: false,
                                recordHistory: true
                            )
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 484)
        .frame(minHeight: 420, idealHeight: 540, maxHeight: 560)
        .onAppear(perform: loadFacts)
    }

    private func factCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial.opacity(0.55))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 0.8) }
        }
    }

    private var formatDisplay: String {
        switch MediaKind.from(path: path) {
        case .still: return NSLocalizedString("kind_still", comment: "")
        case .video: return NSLocalizedString("kind_video", comment: "")
        case .gif: return "GIF"
        case .unknown: return NSLocalizedString("detail_unknown", comment: "")
        }
    }

    private var sourceDisplay: String {
        if let origin = assetRecord?.origin, !origin.isEmpty {
            return origin
        }
        return assetRecord?.source ?? NSLocalizedString("detail_unknown", comment: "")
    }

    private var locationDisplay: String {
        if path.hasPrefix(MoonleafConfigStore.libraryRoot.path) {
            return NSLocalizedString("asset_location_library", comment: "")
        }
        return NSLocalizedString("asset_location_external", comment: "")
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

    private func openPreview() {
        guard fileExists else { return }
        DetailPreviewHost.shared.show(
            path: path,
            title: titleText,
            detail: pixelSize.isEmpty ? nil : pixelSize
        )
    }

    private func copyImage(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let board = NSPasteboard.general
        board.clearContents()
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif"].contains(ext), let image = NSImage(contentsOf: url) {
            board.writeObjects([image, url as NSURL])
        } else {
            board.writeObjects([url as NSURL])
        }
    }
}

struct StorageSettingsSection: View {
    @ObservedObject private var playback = PlaybackCoordinator.shared
    @State private var report = StorageReport.empty
    @State private var lastCleanup = ""
    @State private var showExternalPaths = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Section(title: NSLocalizedString("storage_overview", comment: "")) {
                GlassPanel(cornerRadius: 16, padding: 16, useUltraThin: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        stackedBar

                        HStack(spacing: 16) {
                            legendDot(color: MoonleafPalette.periwinkle, text: libraryText)
                            legendDot(color: MoonleafPalette.mint, text: cacheText)
                            Spacer()
                            ChipButton(
                                title: NSLocalizedString("storage_refresh", comment: ""),
                                icon: "arrow.clockwise",
                                action: refresh
                            )
                        }
                    }
                }
            }

            Section(title: NSLocalizedString("storage_location_title", comment: "")) {
                GlassPanel(cornerRadius: 16, padding: 16, useUltraThin: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(MoonleafConfigStore.libraryRoot.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            ChipButton(
                                title: NSLocalizedString("reveal_finder", comment: ""),
                                icon: "folder"
                            ) {
                                NSWorkspace.shared.activateFileViewerSelecting([MoonleafConfigStore.libraryRoot])
                            }
                        }

                        Text(NSLocalizedString("storage_save_note", comment: ""))
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(title: NSLocalizedString("storage_external_title", comment: "")) {
                GlassPanel(cornerRadius: 16, padding: 16, useUltraThin: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(String(format: NSLocalizedString("storage_external", comment: ""), report.externalPaths.count))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                            Spacer()
                            if !report.externalPaths.isEmpty {
                                ChipButton(
                                    title: showExternalPaths
                                        ? NSLocalizedString("storage_external_hide", comment: "")
                                        : NSLocalizedString("storage_external_show", comment: ""),
                                    trailingIcon: showExternalPaths ? "chevron.up" : "chevron.down",
                                    isActive: showExternalPaths
                                ) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showExternalPaths.toggle()
                                    }
                                }
                            }
                        }

                        if showExternalPaths && !report.externalPaths.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(report.externalPaths, id: \.self) { path in
                                    Text(path)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }

            Section(title: NSLocalizedString("storage_cache_title", comment: "")) {
                GlassPanel(cornerRadius: 16, padding: 16, useUltraThin: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cacheText)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                if !lastCleanup.isEmpty {
                                    Text(lastCleanup)
                                        .font(.system(size: 11, weight: .regular, design: .rounded))
                                        .foregroundStyle(MoonleafPalette.mint)
                                }
                            }
                            Spacer()
                            ChipButton(
                                title: NSLocalizedString("storage_clear_url", comment: ""),
                                icon: "trash"
                            ) {
                                let before = Int64(URLCache.shared.currentDiskUsage)
                                URLCache.shared.removeAllCachedResponses()
                                let after = Int64(URLCache.shared.currentDiskUsage)
                                let beforeText = ByteCountFormatter.string(fromByteCount: before, countStyle: .file)
                                let afterText = ByteCountFormatter.string(fromByteCount: after, countStyle: .file)
                                lastCleanup = String(format: NSLocalizedString("storage_cleared", comment: ""), beforeText, afterText)
                                refresh()
                            }
                        }

                        Divider().opacity(0.4)

                        HStack {
                            Text(NSLocalizedString("storage_memory_note", comment: ""))
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                            ChipButton(
                                title: NSLocalizedString("storage_clear_memory", comment: ""),
                                icon: "memorychip"
                            ) {
                                ImageCache.shared.clear()
                                ImageCache.video.clear()
                            }
                        }
                    }
                }
            }
        }
        .onAppear(perform: refresh)
    }

    private var stackedBar: some View {
        let libraryBytes = max(Int64(0), report.libraryBytes ?? 0)
        let cacheBytes = max(Int64(0), Int64(report.urlCacheBytes))
        let total = max(Int64(1), libraryBytes + cacheBytes)
        let libraryRatio = report.libraryKnown ? CGFloat(libraryBytes) / CGFloat(total) : 0
        let cacheRatio = CGFloat(cacheBytes) / CGFloat(total)

        return GeometryReader { proxy in
            let w = max(proxy.size.width, 1)
            HStack(spacing: 2) {
                if libraryRatio > 0 {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(MoonleafPalette.periwinkle)
                        .frame(width: max(6, w * libraryRatio - 1))
                }
                if cacheRatio > 0 {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(MoonleafPalette.mint)
                        .frame(width: max(6, w * cacheRatio - 1))
                }
                if libraryRatio == 0 && cacheRatio == 0 {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.1))
                }
            }
        }
        .frame(height: 10)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.88))
        }
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
