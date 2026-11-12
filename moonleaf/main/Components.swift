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

// MARK: - Moonleaf Design Tokens & Shared Components

enum MoonleafPalette {
    static let periwinkle = Color(red: 137 / 255, green: 156 / 255, blue: 232 / 255)
    static let primaryGradient = LinearGradient(
        colors: [
            Color(red: 0.42, green: 0.47, blue: 0.85),
            Color(red: 0.32, green: 0.37, blue: 0.75)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let amber = Color(red: 0.92, green: 0.68, blue: 0.32)
    static let mint = Color(red: 0.36, green: 0.78, blue: 0.56)
    static let rose = Color(red: 0.90, green: 0.40, blue: 0.44)
}

struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 16
    var useUltraThin: Bool = true
    var strokeOpacity: Double = 0.12
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(useUltraThin ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.regularMaterial))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.primary.opacity(strokeOpacity), lineWidth: 0.8)
                    }
            }
    }
}

struct GlassToolbar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            content()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial.opacity(0.9))
                .overlay {
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                }
        }
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Font(font_loader.bold(size: 22)))
                    .foregroundStyle(.primary.opacity(0.92))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

struct ChipButton: View {
    let title: String
    var icon: String? = nil
    var trailingIcon: String? = nil
    var isActive: Bool = false
    var tint: Color = MoonleafPalette.periwinkle
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isActive ? tint : Color.secondary)
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(0.85))
                    .lineLimit(1)
                if let trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 11)
                    .fill(isActive ? AnyShapeStyle(tint.opacity(0.18)) : AnyShapeStyle(.regularMaterial.opacity(isHovered ? 0.9 : 0.65)))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(
                                isActive ? tint.opacity(0.5) : Color.primary.opacity(isHovered ? 0.22 : 0.12),
                                lineWidth: 1
                            )
                    }
            }
            .opacity(isDisabled ? 0.45 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}

struct PrimaryGradientButton: View {
    let title: String
    var icon: String? = nil
    var trailingIcon: String? = nil
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                if let trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .opacity(0.85)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(MoonleafPalette.primaryGradient)
                    .brightness(isHovered && !isDisabled ? 0.06 : 0)
            }
            .opacity(isDisabled ? 0.45 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}

struct CircleIconButton: View {
    let icon: String
    var size: CGFloat = 30
    var tint: Color = .primary
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(isDisabled ? Color.secondary.opacity(0.5) : tint.opacity(0.9))
                .frame(width: size, height: size)
                .background {
                    Circle()
                        .fill(.regularMaterial.opacity(isHovered && !isDisabled ? 0.95 : 0.72))
                        .overlay {
                            Circle()
                                .stroke(Color.primary.opacity(isHovered && !isDisabled ? 0.24 : 0.12), lineWidth: 1)
                        }
                }
                .scaleEffect(isHovered && !isDisabled ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}

struct StatusPill: View {
    let text: String
    var icon: String? = nil
    var tint: Color = MoonleafPalette.periwinkle
    var muted: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(muted ? Color.secondary : tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background {
            Capsule()
                .fill(muted ? Color.primary.opacity(0.08) : tint.opacity(0.16))
                .overlay {
                    Capsule()
                        .stroke(muted ? Color.primary.opacity(0.1) : tint.opacity(0.32), lineWidth: 0.8)
                }
        }
    }
}

struct MediaThumb: View {
    let path: String?
    var size: CGSize = CGSize(width: 60, height: 40)
    var cornerRadius: CGFloat = 8
    var showVideoBadge: Bool = true

    private var exists: Bool {
        guard let path, !path.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    private var ext: String {
        guard let path else { return "" }
        return (path as NSString).pathExtension.lowercased()
    }

    var body: some View {
        ZStack {
            if let path, exists {
                if ["gif", "jpg", "jpeg", "png"].contains(ext) {
                    LazyImagePreview(
                        path: path,
                        targetSize: NSSize(width: max(size.width * 2, 120), height: max(size.height * 2, 80))
                    )
                    .id(path)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                } else if ["mp4", "mov"].contains(ext) {
                    videoPreview(
                        videoURL: URL(fileURLWithPath: path),
                        targetSize: NSSize(width: max(size.width * 2, 120), height: max(size.height * 2, 80))
                    )
                    .id(path)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .overlay {
                        if showVideoBadge {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: min(size.height * 0.42, 22)))
                                .foregroundStyle(.white.opacity(0.88))
                                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                        }
                    }
                } else {
                    placeholder(symbol: "photo")
                }
            } else {
                placeholder(symbol: path == nil ? "photo" : "exclamationmark.triangle")
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
        }
    }

    private func placeholder(symbol: String) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: min(size.height * 0.38, 20), weight: .light))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
    }
}

struct GlassSearchField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13, weight: .medium))

            TextField(placeholder, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .onSubmit {
                    onSubmit?()
                }

            if !text.isEmpty {
                Button {
                    text = ""
                    onSubmit?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial.opacity(0.8))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
        }
    }
}

struct GlassEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.primary.opacity(0.4))
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.85))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

struct InlineBanner: View {
    let message: String
    var icon: String = "exclamationmark.triangle.fill"
    var tint: Color = MoonleafPalette.amber
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(tint.opacity(0.14))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(tint.opacity(0.35), lineWidth: 0.8)
                }
        }
    }
}

struct PopoverMenuItem: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var isSelected: Bool = false
    var isDisabled: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isDestructive ? MoonleafPalette.rose : (isSelected ? MoonleafPalette.periwinkle : Color.secondary))
                        .frame(width: 16)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(isDestructive ? MoonleafPalette.rose : (isSelected ? Color.primary : Color.primary.opacity(0.85)))
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MoonleafPalette.periwinkle)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected
                            ? MoonleafPalette.periwinkle.opacity(0.14)
                            : (isHovered && !isDisabled ? Color.primary.opacity(0.08) : Color.primary.opacity(0.001))
                    )
            }
            .opacity(isDisabled ? 0.45 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}
