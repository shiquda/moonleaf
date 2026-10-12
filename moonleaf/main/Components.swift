//
//  Components.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import SwiftUI

struct RippleButton<Label: View>: View {
    var cornerRadius: CGFloat = 14
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .contentShape(Rectangle())
    }
}

struct FavoriteButton: View {
    let isFavorite: Bool
    let action: () -> Void

    @State private var isHovered = false
    @State private var bounce = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { bounce.toggle() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { bounce = false }
            }
            action()
        }) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(Font(font_loader.bold(size: 14)))
                .foregroundStyle(isFavorite ? .yellow : .white)
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                .scaleEffect(bounce ? 1.4 : (isHovered ? 1.15 : 1.0))
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(.black.opacity(isFavorite ? 0.6 : 0.35))
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering } }
    }
}

struct SimpleButton: View {
    let title: String
    let icon: String
    let isPrimary: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        RippleButton(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .foregroundStyle(isPrimary ? .primary : .secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial.opacity(isPrimary ? 0.9 : (isHovered ? 0.7 : 0.5)))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.primary.opacity(isPrimary ? 0.3 : 0.2), lineWidth: 1)
                    }
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

struct VolumeSlider: View {
    enum Style {
        case card
        case menu
    }

    @ObservedObject private var observedService: macpaperService
    private var externalVolume: Binding<Double>?
    private let style: Style
    private let onVolumeChange: (Double) -> Void

    @State private var isHovered = false
    @State private var isDragging = false
    @State private var lastUpdateTime = Date()

    init(
        service: macpaperService = .shared,
        style: Style = .card
    ) {
        self.observedService = service
        self.externalVolume = nil
        self.style = style
        self.onVolumeChange = { newVolume in
            service.chvol(newVolume)
        }
    }

    init(
        volume: Binding<Double>,
        style: Style = .card,
        onVolumeChange: @escaping (Double) -> Void
    ) {
        self.observedService = .shared
        self.externalVolume = volume
        self.style = style
        self.onVolumeChange = onVolumeChange
    }

    private var volumeBinding: Binding<Double> {
        externalVolume ?? $observedService.volume
    }

    private var currentVolume: Double {
        max(0, min(1, volumeBinding.wrappedValue))
    }

    private var speakerIconName: String {
        if currentVolume == 0 {
            return style == .menu ? "speaker.slash" : "speaker.slash.fill"
        } else if style == .menu {
            return "speaker.wave.2"
        } else if currentVolume < 0.33 {
            return "speaker.fill"
        } else if currentVolume < 0.67 {
            return "speaker.wave.1.fill"
        } else {
            return "speaker.wave.2.fill"
        }
    }

    var body: some View {
        switch style {
        case .card:
            cardBody
        case .menu:
            menuBody
        }
    }

    private var menuBody: some View {
        HStack {
            Image(systemName: speakerIconName)
                .font(Font(font_loader.regular(size: 11)))
                .foregroundColor(.secondary)

            Slider(
                value: Binding(
                    get: { currentVolume },
                    set: { newValue in
                        let clamped = max(0, min(1, newValue))
                        volumeBinding.wrappedValue = clamped
                        onVolumeChange(clamped)
                    }
                ),
                in: 0...1
            )
            .frame(width: 120)

            Text("\(Int((currentVolume * 100).rounded()))%")
                .font(Font(font_loader.regular(size: 10)))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 8)
    }

    private var cardBody: some View {
        HStack(spacing: 8) {
            Image(systemName: speakerIconName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.8))
                .frame(width: 16)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.regularMaterial.opacity(0.6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.primary.opacity(0.15), lineWidth: 0.5)
                        }
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(
                            colors: [
                                Color.primary.opacity(0.8),
                                Color.primary.opacity(0.6)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geometry.size.width * currentVolume, height: 12)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white.opacity(isDragging ? 0.3 : 0.2))
                        }

                    Circle()
                        .fill(.regularMaterial)
                        .overlay {
                            Circle()
                                .fill(.white.opacity(0.9))
                                .scaleEffect(0.7)
                        }
                        .overlay {
                            Circle()
                                .stroke(.primary.opacity(0.2), lineWidth: 1)
                        }
                        .frame(width: isDragging ? 18 : 16, height: isDragging ? 18 : 16)
                        .position(
                            x: max(8, min(geometry.size.width - 8, geometry.size.width * currentVolume)),
                            y: geometry.size.height / 2
                        )
                        .scaleEffect(isHovered || isDragging ? 1.1 : 1.0)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isDragging = true
                                }
                            }

                            let newVolume = max(0, min(1, value.location.x / geometry.size.width))
                            volumeBinding.wrappedValue = newVolume

                            let now = Date()
                            if now.timeIntervalSince(lastUpdateTime) > 0.02 {
                                lastUpdateTime = now
                                onVolumeChange(newVolume)
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.easeOut(duration: 0.2)) {
                                isDragging = false
                            }
                            onVolumeChange(currentVolume)
                        }
                )
            }
            .frame(width: 80, height: 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial.opacity(0.9))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.primary.opacity(0.2), lineWidth: 1)
                }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
