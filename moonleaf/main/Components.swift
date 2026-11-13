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
    var size: CGFloat = 28
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
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: size, height: size)
                    .overlay {
                        Circle()
                            .fill(isFavorite ? MoonleafPalette.yellow : Color.black.opacity(0.45))
                            .padding(2)
                    }
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(isHovered ? 0.55 : 0.25), lineWidth: 0.8)
                    }

                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.28), radius: 1, x: 0, y: 1)
                    .scaleEffect(bounce ? 1.25 : (isHovered ? 1.08 : 1.0))
            }
            .frame(width: max(size, 32), height: max(size, 32))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(NSLocalizedString(isFavorite ? "unfavorite_toggle" : "favorite_toggle", comment: ""))
        .accessibilityLabel(NSLocalizedString(isFavorite ? "unfavorite_toggle" : "favorite_toggle", comment: ""))
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
    static let yellow = Color(red: 0.95, green: 0.73, blue: 0.14)
    static let mint = Color(red: 0.24, green: 0.75, blue: 0.52)
    static let blue = Color(red: 0.24, green: 0.52, blue: 0.94)
    static let mutedBlue = Color(red: 0.35, green: 0.53, blue: 0.78)
    static let rose = Color(red: 0.88, green: 0.30, blue: 0.34)
}

struct WidthReader: View {
    let onChange: (CGFloat) -> Void

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(key: WidthPreferenceKey.self, value: geo.size.width)
        }
        .onPreferenceChange(WidthPreferenceKey.self, perform: onChange)
    }
}

private struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 1000
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
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
                        if !useUltraThin {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.32))
                        }
                    }
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
            .foregroundStyle(isDisabled ? Color.secondary : Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isDisabled ? AnyShapeStyle(Color.primary.opacity(0.08)) : AnyShapeStyle(MoonleafPalette.primaryGradient))
                    .brightness(isHovered && !isDisabled ? 0.06 : 0)
                    .overlay {
                        if isDisabled {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 0.8)
                        }
                    }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}

enum CircleActionStyle {
    case neutral
    case darkFrosted
    case filled(Color)

    static let edit = CircleActionStyle.filled(MoonleafPalette.mint)
    static let download = CircleActionStyle.filled(MoonleafPalette.blue)
    static let delete = CircleActionStyle.filled(MoonleafPalette.rose)
    static let playback = CircleActionStyle.filled(MoonleafPalette.periwinkle)
    static let finder = CircleActionStyle.filled(MoonleafPalette.mutedBlue)
    static let removeList = CircleActionStyle.filled(MoonleafPalette.amber)
    static let success = CircleActionStyle.filled(MoonleafPalette.mint)
}

struct CircleIconButton: View {
    let icon: String
    var size: CGFloat = 28
    var tint: Color = .primary
    var style: CircleActionStyle = .neutral
    var isDisabled: Bool = false
    var helpText: String? = nil
    var accessibilityLabelText: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let button = Button(action: action) {
            ZStack {
                switch style {
                case .neutral:
                    Circle()
                        .fill(.regularMaterial)
                        .frame(width: size, height: size)
                        .overlay {
                            Circle()
                                .fill(Color(nsColor: .windowBackgroundColor).opacity(isHovered && !isDisabled ? 0.35 : 0.18))
                        }
                        .overlay {
                            Circle()
                                .stroke(Color.primary.opacity(isHovered && !isDisabled ? 0.28 : 0.14), lineWidth: 1)
                        }
                    Image(systemName: icon)
                        .font(.system(size: size * 0.43, weight: .semibold))
                        .foregroundStyle(isDisabled ? Color.secondary.opacity(0.5) : tint.opacity(0.9))
                case .darkFrosted:
                    Circle()
                        .fill(.regularMaterial)
                        .frame(width: size, height: size)
                        .overlay {
                            Circle()
                                .fill(Color.black.opacity(isHovered && !isDisabled ? 0.65 : 0.48))
                                .padding(2)
                        }
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(isHovered && !isDisabled ? 0.5 : 0.24), lineWidth: 0.8)
                        }
                    Image(systemName: icon)
                        .font(.system(size: size * 0.43, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(isDisabled ? 0.45 : 0.95))
                case .filled(let fill):
                    Circle()
                        .fill(.regularMaterial)
                        .frame(width: size, height: size)
                        .overlay {
                            Circle()
                                .fill(isDisabled ? Color.primary.opacity(0.08) : fill.opacity(isHovered ? 1.0 : 0.90))
                                .padding(2)
                        }
                        .overlay {
                            Circle()
                                .stroke(isDisabled ? Color.primary.opacity(0.14) : Color.white.opacity(isHovered ? 0.55 : 0.22), lineWidth: 0.8)
                        }
                    Image(systemName: icon)
                        .font(.system(size: size * 0.43, weight: .bold))
                        .foregroundStyle(isDisabled ? Color.secondary.opacity(0.8) : Color.white.opacity(0.98))
                        .shadow(color: isDisabled ? .clear : .black.opacity(0.22), radius: 1, x: 0, y: 0.5)
                }
            }
            .frame(width: max(size, 30), height: max(size, 30))
            .contentShape(Circle())
            .opacity(isDisabled ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .background(IconTooltipProbe(text: helpText, hovered: isHovered))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { isHovered = hovering }
        }

        if let helpText, let accessibilityLabelText {
            button.accessibilityLabel(accessibilityLabelText).help(helpText)
        } else if let helpText {
            button.accessibilityLabel(helpText).help(helpText)
        } else if let accessibilityLabelText {
            button.accessibilityLabel(accessibilityLabelText)
        } else {
            button
        }
    }
}

/// A short label above an icon button. System tooltips often never appear
/// inside a sheet, so this uses its own window.
private struct IconTooltipProbe: NSViewRepresentable {
    var text: String?
    var hovered: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let label = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let wants = hovered && !label.isEmpty
        if wants {
            guard let window = nsView.window else { return }
            let rect = window.convertToScreen(nsView.convert(nsView.bounds, to: nil))
            guard rect.width > 0 else { return }
            if context.coordinator.showing, context.coordinator.text == label { return }
            context.coordinator.showing = true
            context.coordinator.text = label
            IconTooltip.shared.schedule(owner: ObjectIdentifier(nsView), text: label, anchor: rect)
        } else if context.coordinator.showing {
            context.coordinator.showing = false
            context.coordinator.text = nil
            IconTooltip.shared.cancel(owner: ObjectIdentifier(nsView))
        }
    }

    final class Coordinator {
        var showing = false
        var text: String?
    }
}

private struct IconTooltipLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.6))
    }
}

private final class IconTooltip {
    static let shared = IconTooltip()
    private var window: NSWindow?
    private var token = UUID()
    private var owner: ObjectIdentifier?

    func schedule(owner: ObjectIdentifier, text: String, anchor: NSRect) {
        let token = UUID()
        self.token = token
        self.owner = owner
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.token == token else { return }
            self.present(text: text, anchor: anchor)
        }
    }

    func cancel(owner: ObjectIdentifier) {
        guard self.owner == owner else { return }
        token = UUID()
        self.owner = nil
        window?.orderOut(nil)
        window = nil
    }

    private func present(text: String, anchor: NSRect) {
        let measured = (text as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        ])
        let size = NSSize(width: ceil(measured.width) + 18, height: ceil(measured.height) + 10)
        let host = NSHostingView(rootView: IconTooltipLabel(text: text))
        host.frame = NSRect(origin: .zero, size: size)
        let window = self.window ?? NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        window.contentView = host
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + 6)
        if let visible = (NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main)?.visibleFrame {
            if origin.y + size.height > visible.maxY {
                origin.y = anchor.minY - size.height - 6
            }
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        }
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        window.orderFrontRegardless()
        self.window = window
    }
}

struct CircleMenuLabel: View {
    var icon: String = "ellipsis"
    var size: CGFloat = 28
    var darkFrosted: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .frame(width: size, height: size)
                .overlay {
                    if darkFrosted {
                        Circle()
                            .fill(Color.black.opacity(0.48))
                            .padding(2)
                    } else {
                        Circle()
                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.22))
                    }
                }
                .overlay {
                    Circle()
                        .stroke(darkFrosted ? Color.white.opacity(0.24) : Color.primary.opacity(0.14), lineWidth: 0.9)
                }
            Image(systemName: icon)
                .font(.system(size: size * 0.43, weight: .semibold))
                .foregroundStyle(darkFrosted ? Color.white.opacity(0.95) : Color.primary.opacity(0.85))
        }
        .frame(width: max(size, 30), height: max(size, 30))
        .contentShape(Circle())
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
