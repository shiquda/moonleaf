//
//  WallpaperCard.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import SwiftUI

struct WallpaperCard: View {
    let wallpaper: endup_wp
    let isActive: Bool
    let cardIsSelected: Bool
    var isMultiSelectMode: Bool = false
    var isMultiSelected: Bool = false
    let onSelect: () -> Void
    let onTap: () -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Void
    let onExport: () -> Void
    let onQuickPreview: () -> Void
    var onToggleMultiSelect: (() -> Void)? = nil
    var onOpenDetail: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editedName = ""
    @State private var showScreenPicker = false
    @FocusState private var isNameFocused: Bool
    @EnvironmentObject private var service: macpaperService
    @ObservedObject private var playback = PlaybackCoordinator.shared

    private var isStillWallpaper: Bool {
        let ext = (wallpaper.path as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png"].contains(ext)
    }

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            previewSection
                .frame(maxWidth: .infinity)
                .onTapGesture {
                    if isMultiSelectMode && !wallpaper.isFolder {
                        onToggleMultiSelect?()
                    } else if wallpaper.isFolder {
                        onTap()
                    } else {
                        onQuickPreview()
                    }
                }
            infoSection
                .frame(height: 56, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isMultiSelectMode && !wallpaper.isFolder {
                        onToggleMultiSelect?()
                    } else {
                        onTap()
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.38))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(
                            isMultiSelected ? MoonleafPalette.periwinkle :
                            cardIsSelected ? MoonleafPalette.periwinkle.opacity(0.8) :
                            isActive ? MoonleafPalette.periwinkle.opacity(0.55) :
                            Color.primary.opacity(isHovered ? 0.24 : 0.12),
                            lineWidth: (isMultiSelected || cardIsSelected) ? 2.2 : (isActive ? 1.8 : 1)
                        )
                }
        }
        .shadow(
            color: .black.opacity(isHovered ? 0.14 : 0.04),
            radius: isHovered ? 10 : 4,
            x: 0,
            y: isHovered ? 4 : 2
        )
        .onAppear {
            service.refreshScreenCount()
        }
        .onChange(of: isEditing) { editing in
            if editing {
                editedName = wallpaper.name
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isNameFocused = true
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) {
                isHovered = hovering
            }
        }
    }

    private var previewSection: some View {
        ZStack {
            Rectangle()
                .fill(Color.brown.opacity(0.2))

            let ext = (wallpaper.path as NSString).pathExtension.lowercased()

            if wallpaper.isFolder {
                VStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
            } else if ["gif", "jpg", "jpeg", "png"].contains(ext) {
                LazyImagePreview(path: wallpaper.path, targetSize: NSSize(width: 320, height: 200))
            } else if ["mp4", "mov"].contains(ext) {
                videoPreview(videoURL: URL(fileURLWithPath: wallpaper.path), targetSize: NSSize(width: 320, height: 200))
                    .clipped()
                    .overlay {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.white.opacity(0.8))
                            .background {
                                Circle()
                                    .fill(.black.opacity(0.3))
                                    .frame(width: 40, height: 40)
                            }
                    }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.secondary)
            }

            if !wallpaper.isFolder {
                if isMultiSelectMode {
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(isMultiSelected ? MoonleafPalette.periwinkle : Color.black.opacity(0.35))
                                    .frame(width: 26, height: 26)
                                    .overlay {
                                        Circle()
                                            .stroke(.white.opacity(0.8), lineWidth: 1.5)
                                    }
                                if isMultiSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(10)
                        }
                        Spacer()
                    }
                } else if isHovered || isActive || cardIsSelected {
                    overlayControls
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.9)),
                            removal: .opacity.combined(with: .scale(scale: 1.1))
                        ))
                } else {
                    VStack {
                        HStack {
                            Spacer()
                            cardActionMenu
                                .padding(10)
                        }
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 176)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isMultiSelected ? MoonleafPalette.periwinkle.opacity(0.75) :
                    isActive ? Color.primary.opacity(0.35) : Color.primary.opacity(0.1),
                    lineWidth: (isActive || isMultiSelected) ? 1.8 : 1
                )
        }
    }

    private var cardActionMenu: some View {
        Menu {
            Button(NSLocalizedString("apply_current", comment: "")) { onSelect() }
            Button(NSLocalizedString("apply_display", comment: "")) {
                if let uuid = SpaceBinding.currentDisplayUUID() {
                    service.applyToDisplayDesktops(wallpaper, displayUUID: uuid, confirmedCrossDisplay: false)
                }
            }
            if let onOpenDetail {
                Button(NSLocalizedString("detail_open", comment: "")) { onOpenDetail() }
            }
            Button(service.isFavorite(wallpaper) ? NSLocalizedString("unfavorite_toggle", comment: "") : NSLocalizedString("favorite_toggle", comment: "")) {
                service.toggleFavorite(wallpaper)
            }
            if !playback.playlists.isEmpty {
                Menu(NSLocalizedString("browse_add_to_playlist", comment: "")) {
                    ForEach(playback.playlists) { list in
                        Button(list.name) {
                            playback.addToPlaylist(paths: [wallpaper.path], playlistID: list.id)
                        }
                    }
                }
            }
            if let onToggleMultiSelect {
                Button(isMultiSelected ? NSLocalizedString("library_unselect", comment: "") : NSLocalizedString("library_select", comment: "")) {
                    onToggleMultiSelect()
                }
            }
            Divider()
            Button(NSLocalizedString("library_rename", comment: "")) { isEditing = true }
            Button(NSLocalizedString("library_export", comment: "")) { onExport() }
            Button(NSLocalizedString("history_remove", comment: ""), role: .destructive) { onDelete() }
        } label: {
            CircleMenuLabel(darkFrosted: true)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(.white)
        .frame(width: 30, height: 30)
        .fixedSize()
        .help(NSLocalizedString("detail_open", comment: ""))
    }

    private var overlayControls: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .black.opacity(0.6),
                    .black.opacity(0.3),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                HStack(spacing: 6) {
                    if isActive {
                        ZStack {
                            Circle()
                                .fill(.regularMaterial)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    Circle()
                                        .fill(MoonleafPalette.mint)
                                        .padding(2)
                                }
                                .overlay {
                                    Circle()
                                        .stroke(Color.white.opacity(0.28), lineWidth: 0.8)
                                }
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 30, height: 30)
                        .accessibilityLabel(NSLocalizedString("active_label", comment: ""))
                    }

                    FavoriteButton(
                        isFavorite: service.isFavorite(wallpaper),
                        action: { service.toggleFavorite(wallpaper) }
                    )

                    Spacer(minLength: 4)

                    HStack(spacing: 5) {
                        CircleIconButton(
                            icon: "pencil",
                            style: .edit,
                            helpText: NSLocalizedString("library_rename", comment: "")
                        ) {
                            isEditing = true
                        }

                        CircleIconButton(
                            icon: "arrow.down.circle",
                            style: .download,
                            helpText: NSLocalizedString("library_export", comment: "")
                        ) {
                            onExport()
                        }

                        CircleIconButton(
                            icon: "trash",
                            style: .delete,
                            helpText: NSLocalizedString("history_remove", comment: "")
                        ) {
                            onDelete()
                        }

                        cardActionMenu
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)

                Spacer()
                if !isActive {
                    if service.screenCount > 1 && !isStillWallpaper {
                        VStack(spacing: 6) {
                            if showScreenPicker {
                                HStack(spacing: 6) {
                                    Button(action: {
                                        showScreenPicker = false
                                        onSelect()
                                    }) {
                                        VStack(spacing: 3) {
                                            Image(systemName: "display.2")
                                                .font(.system(size: 13, weight: .medium))
                                            Text("All")
                                                .font(.system(size: 9, weight: .medium))
                                        }
                                        .foregroundStyle(.white)
                                        .frame(width: 44, height: 36)
                                        .background {
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color(red: 0.42, green: 0.47, blue: 0.85).opacity(0.85))
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    ForEach(0..<service.screenCount, id: \.self) { idx in
                                        Button(action: {
                                            showScreenPicker = false
                                            service.set_wp_on_screen(wallpaper, screenIndex: idx)
                                        }) {
                                            VStack(spacing: 3) {
                                                Image(systemName: "display")
                                                    .font(.system(size: 13, weight: .medium))
                                                Text("\(idx + 1)")
                                                    .font(.system(size: 9, weight: .bold))
                                            }
                                            .foregroundStyle(.white)
                                            .frame(width: 36, height: 36)
                                            .background {
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(Color.white.opacity(0.15))
                                                    .overlay {
                                                        RoundedRectangle(cornerRadius: 10)
                                                            .stroke(.white.opacity(0.3), lineWidth: 1)
                                                    }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                                    removal: .scale(scale: 0.8).combined(with: .opacity)
                                ))
                            } else {
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        showScreenPicker = true
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "wand.and.stars")
                                            .font(.system(size: 13, weight: .medium))
                                        Text(NSLocalizedString("set_wallpaper", comment: "set wallpaper"))
                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 10, weight: .semibold))
                                            .opacity(0.7)
                                    }
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background {
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(.regularMaterial.opacity(0.9))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 16)
                                                    .stroke(.primary.opacity(0.3), lineWidth: 1)
                                            }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showScreenPicker)
                        .padding(.bottom, 12)
                    } else {
                        SimpleButton(
                            title: NSLocalizedString("set_wallpaper", comment: "set wallpaper"),
                            icon: "wand.and.stars",
                            isPrimary: true,
                            action: onSelect
                        )
                        .padding(.bottom, 12)
                    }
                } else if isActive && !isStillWallpaper {
                    VolumeSlider(service: service, style: .card)
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 176)
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isEditing {
                HStack(spacing: 4) {
                    TextField("", text: $editedName)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.9))
                        .focused($isNameFocused)
                        .onSubmit {
                            saveName()
                        }

                    Button(action: saveName) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        isEditing = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.1))
                )
            } else {
                Text(wallpaper.name)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.92))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(wallpaper.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                let ext = (wallpaper.path as NSString).pathExtension.lowercased()

                let fileType: String = {
                    if wallpaper.isFolder {
                        return NSLocalizedString("kind_folder", comment: "")
                    } else if ["mp4", "mov"].contains(ext) {
                        return NSLocalizedString("kind_video", comment: "")
                    } else if ext == "gif" {
                        return "GIF"
                    } else if ["jpg", "jpeg", "png"].contains(ext) {
                        return NSLocalizedString("kind_still", comment: "")
                    } else {
                        return NSLocalizedString("detail_unknown", comment: "")
                    }
                }()

                StatusPill(text: fileType, muted: true)

                Spacer()

                Text(ByteCountFormatter.string(fromByteCount: wallpaper.fileSize, countStyle: .file))
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.85))
            }
        }
    }

    private func saveName() {
        if !editedName.isEmpty && editedName != wallpaper.name {
            onRename(editedName)
        }
        isEditing = false
    }
}
