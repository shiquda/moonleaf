//
//  WallpaperInspectorOverlay.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import SwiftUI

struct WPCUtilOverlay: View {
    let wallpaper: endup_wp
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            Group {
                let ext = (wallpaper.path as NSString).pathExtension.lowercased()

                if ["gif", "jpg", "jpeg", "png"].contains(ext) {
                    LazyImagePreview(path: wallpaper.path, targetSize: NSSize(width: 60, height: 40))
                        .id(wallpaper.id)
                        .frame(width: 60, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if ["mp4", "mov"].contains(ext) {
                    videoPreview(videoURL: URL(fileURLWithPath: wallpaper.path), targetSize: NSSize(width: 60, height: 40))
                        .id(wallpaper.id)
                        .frame(width: 60, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 60, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .transition(.opacity)

            VStack(alignment: .leading, spacing: 4) {
                Text(wallpaper.name)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)

                Text(ByteCountFormatter.string(fromByteCount: wallpaper.fileSize, countStyle: .file))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle()
                            .fill(.regularMaterial)
                            .overlay {
                                Circle()
                                    .stroke(.primary.opacity(0.1), lineWidth: 1)
                            }
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(width: 300)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.primary.opacity(0.1), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        }
        .padding(.bottom, 20)
        .transition(.opacity)
    }
}
