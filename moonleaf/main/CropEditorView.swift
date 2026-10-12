//
//  CropEditorView.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import SwiftUI
import AppKit

struct CropEditorView: View {
    let image: NSImage
    let wallpaperName: String
    let onCrop: (CGRect, CGSize) -> Void
    let onCancel: () -> Void

    @State private var selectedRatioIndex: Int = 0
    @State private var imageSize: CGSize = .zero
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var zoomScale: CGFloat = 1.0

    struct RatioOption: Identifiable {
        let id: String
        let name: String
        let size: CGSize
        var aspectRatio: CGFloat { size.width / size.height }
    }

    private let ratios: [RatioOption] = [
        RatioOption(id: "iphone15promax", name: "iPhone 15 Pro Max", size: CGSize(width: 1290, height: 2796)),
        RatioOption(id: "iphone15pro", name: "iPhone 15 Pro", size: CGSize(width: 1179, height: 2556)),
        RatioOption(id: "iphone14pro", name: "iPhone 14 Pro", size: CGSize(width: 1179, height: 2556)),
        RatioOption(id: "iphone13pro", name: "iPhone 13 Pro", size: CGSize(width: 1170, height: 2532)),
        RatioOption(id: "iphonese", name: "iPhone SE", size: CGSize(width: 750, height: 1334)),
        RatioOption(id: "ipadpro12", name: "iPad Pro 12.9\"", size: CGSize(width: 2732, height: 2048)),
        RatioOption(id: "ipadpro11", name: "iPad Pro 11\"", size: CGSize(width: 2388, height: 1668)),
        RatioOption(id: "4k", name: "4K UHD (3840×2160)", size: CGSize(width: 3840, height: 2160)),
        RatioOption(id: "1440p", name: "1440p (2560×1440)", size: CGSize(width: 2560, height: 1440)),
        RatioOption(id: "1080p", name: "1080p (1920×1080)", size: CGSize(width: 1920, height: 1080)),
        RatioOption(id: "ultrawide", name: "Ultrawide 21:9", size: CGSize(width: 3440, height: 1440))
    ]

    private var selectedRatio: RatioOption { ratios[selectedRatioIndex] }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                headerView
                cropCanvas
                controlsView
            }
            .frame(maxWidth: .infinity)

            Divider()

            ratioSidebar
                .frame(width: 220)
        }
        .frame(minWidth: 900, minHeight: 650)
        .onAppear {
            loadImageSize()
        }
    }

    private var headerView: some View {
        HStack {
            Text(NSLocalizedString("crop_editor_title", comment: "Crop Image"))
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var cropCanvas: some View {
        GeometryReader { geo in
            let canvasSize = geo.size
            let cropFrameSize = calculateCropFrameSize(in: canvasSize)
            let imageDisplaySize = calculateImageDisplaySize(for: cropFrameSize)
            let clampedOffset = clampOffset(imageSize: imageDisplaySize, cropSize: cropFrameSize)

            ZStack {
                Color(NSColor.darkGray).opacity(0.3)

                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: imageDisplaySize.width, height: imageDisplaySize.height)
                        .offset(clampedOffset)
                }
                .frame(width: cropFrameSize.width, height: cropFrameSize.height)
                .clipped()
                .overlay(
                    Rectangle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .overlay(cropGridOverlay(size: cropFrameSize))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let newOffset = CGSize(
                                width: lastPanOffset.width + value.translation.width,
                                height: lastPanOffset.height + value.translation.height
                            )
                            panOffset = newOffset
                        }
                        .onEnded { _ in
                            lastPanOffset = clampOffset(imageSize: imageDisplaySize, cropSize: cropFrameSize)
                            panOffset = lastPanOffset
                        }
                )

                VStack {
                    Spacer()
                    HStack {
                        Text("\(Int(selectedRatio.size.width)) × \(Int(selectedRatio.size.height))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                    }
                    .padding(.bottom, 8)
                }
                .frame(width: cropFrameSize.width, height: cropFrameSize.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
    }

    private func cropGridOverlay(size: CGSize) -> some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: size.width / 3, y: 0))
                path.addLine(to: CGPoint(x: size.width / 3, y: size.height))
                path.move(to: CGPoint(x: size.width * 2 / 3, y: 0))
                path.addLine(to: CGPoint(x: size.width * 2 / 3, y: size.height))
                path.move(to: CGPoint(x: 0, y: size.height / 3))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 3))
                path.move(to: CGPoint(x: 0, y: size.height * 2 / 3))
                path.addLine(to: CGPoint(x: size.width, y: size.height * 2 / 3))
            }
            .stroke(Color.white.opacity(0.4), lineWidth: 1)
        }
    }

    private var controlsView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Text(NSLocalizedString("crop_zoom", comment: "Zoom"))
                    .font(.system(size: 12))
                    .frame(width: 40, alignment: .leading)

                Slider(value: $zoomScale, in: 1.0...3.0, step: 0.1)
                    .frame(maxWidth: 300)

                Text(String(format: "%.1fx", zoomScale))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .frame(width: 40)

                Button(action: resetCrop) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text(NSLocalizedString("browse_cancel", comment: "Cancel"))
                        .frame(width: 100)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape)

                Button(action: performCrop) {
                    Text(NSLocalizedString("crop_apply", comment: "Apply"))
                        .frame(width: 100)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var ratioSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString("export_aspect_ratio", comment: "Aspect Ratio"))
                .font(.system(size: 13, weight: .semibold))
                .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sectionHeader("iPhone")
                    ForEach(0..<5) { i in
                        ratioRow(index: i)
                    }

                    sectionHeader("iPad")
                    ForEach(5..<7) { i in
                        ratioRow(index: i)
                    }

                    sectionHeader("Desktop")
                    ForEach(7..<ratios.count) { i in
                        ratioRow(index: i)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func ratioRow(index: Int) -> some View {
        let ratio = ratios[index]
        let isSelected = selectedRatioIndex == index

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedRatioIndex = index
                resetCrop()
            }
        }) {
            HStack {
                Text(ratio.name)
                    .font(.system(size: 12))
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func loadImageSize() {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            imageSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        }
    }

    private func calculateCropFrameSize(in canvasSize: CGSize) -> CGSize {
        let targetRatio = selectedRatio.aspectRatio
        let maxWidth = canvasSize.width * 0.85
        let maxHeight = canvasSize.height * 0.85

        var width: CGFloat
        var height: CGFloat

        if maxWidth / maxHeight > targetRatio {
            height = maxHeight
            width = height * targetRatio
        } else {
            width = maxWidth
            height = width / targetRatio
        }

        return CGSize(width: width, height: height)
    }

    private func calculateImageDisplaySize(for cropSize: CGSize) -> CGSize {
        guard imageSize.width > 0 && imageSize.height > 0 else {
            return cropSize
        }

        let imageRatio = imageSize.width / imageSize.height
        let cropRatio = cropSize.width / cropSize.height

        var baseWidth: CGFloat
        var baseHeight: CGFloat

        if imageRatio > cropRatio {
            baseHeight = cropSize.height
            baseWidth = baseHeight * imageRatio
        } else {
            baseWidth = cropSize.width
            baseHeight = baseWidth / imageRatio
        }

        return CGSize(width: baseWidth * zoomScale, height: baseHeight * zoomScale)
    }

    private func clampOffset(imageSize: CGSize, cropSize: CGSize) -> CGSize {
        let maxX = max(0, (imageSize.width - cropSize.width) / 2)
        let maxY = max(0, (imageSize.height - cropSize.height) / 2)

        return CGSize(
            width: min(maxX, max(-maxX, panOffset.width)),
            height: min(maxY, max(-maxY, panOffset.height))
        )
    }

    private func resetCrop() {
        panOffset = .zero
        lastPanOffset = .zero
        zoomScale = 1.0
    }

    private func performCrop() {
        guard imageSize.width > 0 && imageSize.height > 0 else { return }

        let targetRatio = selectedRatio.aspectRatio
        let imageRatio = imageSize.width / imageSize.height

        var baseCropWidth: CGFloat
        var baseCropHeight: CGFloat

        if imageRatio > targetRatio {
            baseCropHeight = imageSize.height
            baseCropWidth = baseCropHeight * targetRatio
        } else {
            baseCropWidth = imageSize.width
            baseCropHeight = baseCropWidth / targetRatio
        }

        let cropWidth = baseCropWidth / zoomScale
        let cropHeight = baseCropHeight / zoomScale

        let imageDisplaySize = CGSize(
            width: imageRatio > targetRatio ? imageSize.height * targetRatio * zoomScale : imageSize.width * zoomScale,
            height: imageRatio > targetRatio ? imageSize.height * zoomScale : imageSize.width / targetRatio * zoomScale
        )

        let normalizedOffsetX = -panOffset.width / imageDisplaySize.width
        let normalizedOffsetY = -panOffset.height / imageDisplaySize.height

        let centerX = imageSize.width / 2
        let centerY = imageSize.height / 2

        let cropCenterX = centerX + normalizedOffsetX * imageSize.width
        let cropCenterY = centerY + normalizedOffsetY * imageSize.height

        var cropX = cropCenterX - cropWidth / 2
        var cropY = cropCenterY - cropHeight / 2

        cropX = max(0, min(imageSize.width - cropWidth, cropX))
        cropY = max(0, min(imageSize.height - cropHeight, cropY))

        let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)

        onCrop(cropRect, selectedRatio.size)
    }
}
