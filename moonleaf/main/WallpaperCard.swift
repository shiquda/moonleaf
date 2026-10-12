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
    let onSelect: () -> Void
    let onTap: () -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Void
    let onExport: () -> Void
    let onQuickPreview: () -> Void

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editedName = ""
    @State private var showScreenPicker = false
    @FocusState private var isNameFocused: Bool
    @EnvironmentObject private var service: macpaperService

    private var isStillWallpaper: Bool {
        let ext = (wallpaper.path as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png"].contains(ext)
    }

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            previewSection
                .frame(maxWidth: .infinity)
                .onTapGesture {
                    if wallpaper.isFolder {
                        onTap()
                    } else {
                        onQuickPreview()
                    }
                }
            infoSection
                .frame(height: 50)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    onTap()
                }
        }
        .frame(width: 300, height: 260)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(.regularMaterial.opacity(0.8))
                .overlay {
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(
                            cardIsSelected ? Color.blue.opacity(0.6) :
                            isActive ? Color.primary.opacity(0.4) : Color.primary.opacity(0.1),
                            lineWidth: cardIsSelected ? 3 : (isActive ? 2 : 1)
                        )
                }
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
                LazyImagePreview(path: wallpaper.path)
            } else if ["mp4", "mov"].contains(ext) {
                videoPreview(videoURL: URL(fileURLWithPath: wallpaper.path))
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

            if isHovered || isActive {
                overlayControls
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9)),
                        removal: .opacity.combined(with: .scale(scale: 1.1))
                    ))
            }
        }
        .frame(width: 276, height: 184)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isActive
                        ? Color.primary.opacity(0.4)
                        : Color.primary.opacity(0.1),
                    lineWidth: isActive ? 2 : 1
                )
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
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
                HStack {
                    if isActive {
                        Circle()
                            .fill(.green.opacity(0.9))
                            .frame(width: 24, height: 24)
                            .overlay {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .background {
                                Circle()
                                    .fill(.regularMaterial)
                                    .frame(width: 28, height: 28)
                            }
                    }

                    FavoriteButton(
                        isFavorite: service.isFavorite(wallpaper),
                        action: { service.toggleFavorite(wallpaper) }
                    )

                    Spacer()

                    if isActive && !isStillWallpaper {
                        VolumeSlider(service: service, style: .card)
                            .scaleEffect(0.85)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                removal: .scale(scale: 0.8).combined(with: .opacity)
                            ))
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button(action: {
                            isEditing = true
                        }) {
                            Circle()
                                .fill(.mint.opacity(0.9))
                                .frame(width: 24, height: 24)
                                .overlay {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.white)
                                }
                                .background {
                                    Circle()
                                        .fill(.regularMaterial)
                                        .frame(width: 28, height: 28)
                                }
                        }
                        .buttonStyle(.plain)

                        Button(action: onExport) {
                            Circle()
                                .fill(.blue.opacity(0.9))
                                .frame(width: 24, height: 24)
                                .overlay {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.white)
                                }
                                .background {
                                    Circle()
                                        .fill(.regularMaterial)
                                        .frame(width: 28, height: 28)
                                }
                        }
                        .buttonStyle(.plain)

                        Button(action: onDelete) {
                            Circle()
                                .fill(.red.opacity(0.9))
                                .frame(width: 24, height: 24)
                                .overlay {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.white)
                                }
                                .background {
                                    Circle()
                                        .fill(.regularMaterial)
                                        .frame(width: 28, height: 28)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

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
                }
            }
        }
        .frame(width: 276, height: 184)
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
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(2)
            }

            HStack {
                let ext = (wallpaper.path as NSString).pathExtension.lowercased()

                let fileType = wallpaper.isFolder ? "folder" :
                            ["mp4", "mov"].contains(ext) ? "video" :
                            ext == "gif" ? "gif" :
                            ["jpg", "jpeg", "png"].contains(ext) ? "image" : "unknown"

                Text(fileType)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background {
                        Capsule()
                            .fill(Color.brown.opacity(0.3))
                    }

                Spacer()

                Text(ByteCountFormatter.string(fromByteCount: wallpaper.fileSize, countStyle: .file))
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.8))
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
