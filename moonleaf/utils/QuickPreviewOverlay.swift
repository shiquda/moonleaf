//
//  QuickPreviewOverlay.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import SwiftUI
import AVKit

/// What the full-screen preview shows: a wallpaper that lives in the library, or
/// a remote result from the browse view. `url.isFileURL` decides how it loads —
/// library wallpaper read from disk, browse results stream over https.
struct PreviewTarget {
    let url: URL
    let title: String
    /// Appended to the media type in the caption, e.g. file size or resolution.
    let detail: String?
}

struct QuickPreviewOverlay: View {
    let target: PreviewTarget
    let onClose: () -> Void
    
    @State private var isHovered = false
    @State private var currentTime = Date()
    @State private var isVisible = false
    @State private var player: AVPlayer?
    @State private var isVideoPlaying = true
    @State private var zoom: CGFloat = 1
    @State private var pinch: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var drag: CGSize = .zero
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private var fileExtension: String {
        target.url.pathExtension.lowercased()
    }
    
    private var isVideo: Bool {
        ["mp4", "mov"].contains(fileExtension)
    }
    
    private var isStillImage: Bool {
        ["jpg", "jpeg", "png", "gif"].contains(fileExtension)
    }
    
    /// The wallpaper itself; `body` puts it in the zoom and pan container.
    private var mediaContent: some View {
        Group {
            if isVideo {
                videoContent
            } else if fileExtension == "gif" && target.url.isFileURL {
                GIFAnimatingView(path: target.url.path)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isStillImage && target.url.isFileURL {
                if let image = NSImage(contentsOfFile: target.url.path) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    unreadableMedia
                }
            } else if isStillImage {
                // Browse results are streamed from the provider instead of disk.
                AsyncImage(url: target.url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure:
                        unreadableMedia
                    default:
                        loadingMedia
                    }
                }
            } else {
                unsupportedMedia
            }
        }
    }
    
    private var videoContent: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        if isVideoPlaying {
                            player.play()
                        }
                    }
                    .onDisappear {
                        player.pause()
                    }
                    .onTapGesture {
                        if isVideoPlaying {
                            player.pause()
                        } else {
                            player.play()
                        }
                        isVideoPlaying.toggle()
                    }
                    .overlay(
                        Group {
                            if !isVideoPlaying {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.white.opacity(0.6))
                                    .shadow(color: .black.opacity(0.5), radius: 10)
                            }
                        }
                    )
            } else {
                loadingMedia
            }
        }
    }
    
    private var loadingMedia: some View {
        Color.gray.opacity(0.3)
            .overlay {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
    }
    
    private var unreadableMedia: some View {
        Color.gray.opacity(0.3)
            .overlay {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(.white.opacity(0.5))
            }
    }
    
    private var unsupportedMedia: some View {
        Color.gray.opacity(0.3)
            .overlay {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.white.opacity(0.5))
            }
    }
    
    /// Keeps a zoomed wallpaper from being dragged off screen: the further you
    /// zoom in, the further the picture may travel.
    private func panOffset(in size: CGSize) -> CGSize {
        let scale = zoom * pinch
        let limitX = max(0, (scale - 1) * size.width / 2)
        let limitY = max(0, (scale - 1) * size.height / 2)
        return CGSize(
            width: min(max(pan.width + drag.width, -limitX), limitX),
            height: min(max(pan.height + drag.height, -limitY), limitY)
        )
    }
    
    private func resetZoom() {
        withAnimation(.easeOut(duration: 0.2)) {
            zoom = 1
            pinch = 1
            pan = .zero
            drag = .zero
        }
    }
    
    private func toggleZoom() {
        withAnimation(.easeOut(duration: 0.2)) {
            zoom = zoom > 1 ? 1 : 2
            pan = .zero
            drag = .zero
        }
    }
    
    /// Steps the zoom up for pointer users, who have no pinch gesture.
    private func zoomIn() {
        withAnimation(.easeOut(duration: 0.2)) {
            zoom = min(zoom * pinch * 2, 6)
            pinch = 1
        }
    }
    
    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                pinch = value
            }
            .onEnded { value in
                withAnimation(.easeOut(duration: 0.2)) {
                    zoom = min(max(zoom * value, 1), 6)
                    pinch = 1
                    if zoom == 1 {
                        pan = .zero
                        drag = .zero
                    }
                }
            }
    }
    
    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoom * pinch > 1 else { return }
                drag = value.translation
            }
            .onEnded { _ in
                pan.width += drag.width
                pan.height += drag.height
                drag = .zero
            }
    }
    
    var body: some View {
        ZStack {
            
            Color.black
                .ignoresSafeArea()
            
            
            GeometryReader { geo in
                mediaContent
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(zoom * pinch)
                    .offset(panOffset(in: geo.size))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { toggleZoom() }
                    .gesture(zoomGesture)
                    .simultaneousGesture(panGesture)
            }
            .clipped()
            .ignoresSafeArea()
            
            
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    VStack(spacing: 0) {
                        
                        Text(formatDate(currentTime))
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.bottom, -3)
                        
                        
                        Text(formatTime(currentTime))
                            .font(.system(size: 96, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.95))
                    }
                    .padding(.top, 60)
                    Spacer()
                }
                Spacer()
            }
            .ignoresSafeArea()
            
            
            VStack {
                Spacer()
                
                HStack(spacing: 20) {
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.title)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                        
                        let ext = fileExtension
                        let fileType = isVideo ? NSLocalizedString("preview_type_video", comment: "Video") :
                                      ext == "gif" ? NSLocalizedString("preview_type_gif", comment: "GIF") :
                                      ["jpg", "jpeg", "png"].contains(ext) ? NSLocalizedString("preview_type_image", comment: "Image") :
                                      NSLocalizedString("preview_type_file", comment: "File")
                        Text([fileType, target.detail].compactMap { $0 }.joined(separator: " • "))
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Spacer()
                    
                    if zoom * pinch > 1.001 {
                        Button(action: resetZoom) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(String(format: "%.1f×", zoom * pinch))
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(.regularMaterial.opacity(0.8))
                                    .overlay {
                                        Capsule()
                                            .stroke(.white.opacity(0.2), lineWidth: 1)
                                    }
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                    } else {
                        Button(action: zoomIn) {
                            Image(systemName: "plus.magnifyingglass")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 5)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                    }
                    
                    if isVideo {
                        Button(action: {
                            if isVideoPlaying {
                                player?.pause()
                            } else {
                                player?.play()
                            }
                            isVideoPlaying.toggle()
                        }) {
                            Image(systemName: isVideoPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 5)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                    }
                    
                    
                    Button(action: onClose) {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                            Text(NSLocalizedString("preview_close", comment: "Close Preview"))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(.regularMaterial.opacity(0.8))
                                .overlay {
                                    Capsule()
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                }
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.15)) {
                            isHovered = hovering
                        }
                    }
                    // .scaleEffect(isHovered ? 1.05 : 1.0)
                    
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
            .opacity(isVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.3).delay(0.2), value: isVisible)
        }
        .onAppear {
            
            if isVideo {
                player = AVPlayer(url: target.url)
                player?.volume = 0 
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    player?.play()
                }
            }
            
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isVisible = true
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: date)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }
}

struct GIFAnimatingView: NSViewRepresentable {
    let path: String
    
    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        return imageView
    }
    
    func updateNSView(_ nsView: NSImageView, context: Context) {
        if let image = NSImage(contentsOfFile: path) {
            nsView.image = image
        }
    }
}