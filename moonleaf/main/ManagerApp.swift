//
//  ManagerApp.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ManagerView: View {
    @ObservedObject private var service = macpaperService.shared
    @State private var show_importer = false
    @State private var importingFolder = false
    @State private var showAddPopover = false
    @State private var file_drag = false
    @State private var showFavoritesOnly = false
    @State private var showFilterDropdown = false
    @State private var showSortDropdown = false
    @State private var showWpActionsDropdown = false
    @Binding var previewTarget: PreviewTarget?

    private static let supportedExtensions: Set<String> = ["mp4", "mov", "gif", "jpg", "jpeg", "png"]

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                toolbarView
                contentView
            }

            if let wallpaper = service.selected_wp {
                WPCUtilOverlay(
                    wallpaper: wallpaper,
                    onClose: {
                        withAnimation(.easeOut(duration: 0.3)) {
                            service.select_wp(nil)
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: service.selected_wp?.id)
        .onAppear {
            service.fetch_wallpapers()
        }
        .fileImporter(
            isPresented: $show_importer,
            allowedContentTypes: importingFolder ? [.folder] : [.movie, .image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    import_wp(from: url)
                }
            case .failure(let error):
                print("import error: \(error)")
            }
        }
    }

    private var toolbarView: some View {
        HStack(spacing: 12) {
            Button(action: { showAddPopover.toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text("add wallpaper")
                        .font(Font(font_loader.bold(size: 13)))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .opacity(0.8)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(width: 175)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.47, blue: 0.85), Color(red: 0.32, green: 0.37, blue: 0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAddPopover, arrowEdge: .bottom) {
                VStack(spacing: 4) {
                    Button(action: {
                        importingFolder = false
                        showAddPopover = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            show_importer = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "doc.fill")
                            Text("file")
                            Spacer()
                        }
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.001)))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        importingFolder = true
                        showAddPopover = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            show_importer = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "folder.fill")
                            Text("folder")
                            Spacer()
                        }
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.001)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .frame(width: 160)
            }

            Button(action: { show_settings() }) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                    Text(NSLocalizedString("mgr_settings", comment: "settings"))
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)

            Spacer()

            if let currentWp = service.current_wp {
                Button(action: { showWpActionsDropdown.toggle() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13))
                        Text("Active Wallpaper")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(showWpActionsDropdown ? 0.15 : 0.05)))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showWpActionsDropdown, arrowEdge: .bottom) {
                    VStack(spacing: 4) {
                        if !isStillWallpaper(currentWp) {
                            Button(action: { service.wp_doPersist(!service.wp_is_agent); showWpActionsDropdown = false }) {
                                HStack {
                                    Image(systemName: service.wp_is_agent ? "checkmark.circle.fill" : "circle")
                                    Text(NSLocalizedString("persist", comment: ""))
                                    Spacer()
                                }
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.001)))
                            }
                            .buttonStyle(.plain)
                        }
                        Button(action: { service.unset_wp(); showWpActionsDropdown = false }) {
                            HStack {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.red)
                                Text(NSLocalizedString("unset_current", comment: ""))
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .frame(width: 170)
                }
            }

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) { showFavoritesOnly.toggle() }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(showFavoritesOnly ? .yellow : .secondary)
                    if showFavoritesOnly {
                        Text(NSLocalizedString("favorites_filter", comment: ""))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.regularMaterial.opacity(showFavoritesOnly ? 0.9 : 0.5))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(showFavoritesOnly ? Color.yellow.opacity(0.4) : Color.primary.opacity(0.15), lineWidth: 1)
                        }
                }
            }
            .buttonStyle(.plain)

            Button(action: { showFilterDropdown.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 13, weight: .semibold))
                    Text(NSLocalizedString("filter", comment: "Filter"))
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(showFilterDropdown ? 0.15 : 0.05)))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showFilterDropdown, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("show_types", comment: "Show"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)

                    Button(action: {
                        service.showVideos.toggle()
                        service.saveSettings()
                        service.fetch_wallpapers()
                    }) {
                        HStack {
                            Text(NSLocalizedString("show_videos", comment: "Videos"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(service.showVideos ? .primary : .secondary)
                            Spacer()
                            if service.showVideos {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(service.showVideos ? 0.08 : 0.001)))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        service.showImages.toggle()
                        service.saveSettings()
                        service.fetch_wallpapers()
                    }) {
                        HStack {
                            Text(NSLocalizedString("show_images", comment: "Images"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(service.showImages ? .primary : .secondary)
                            Spacer()
                            if service.showImages {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(service.showImages ? 0.08 : 0.001)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .frame(width: 160)
            }

            Button(action: { showSortDropdown.toggle() }) {
                HStack(spacing: 6) {
                    Text(service.localSort.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(showSortDropdown ? 0.15 : 0.05)))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSortDropdown, arrowEdge: .bottom) {
                VStack(spacing: 4) {
                    ForEach(macpaperService.LocalSortMode.allCases, id: \.self) { mode in
                        Button(action: { service.setLocalSort(mode); showSortDropdown = false }) {
                            HStack {
                                Text(mode.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(service.localSort == mode ? .primary : .secondary)
                                Spacer()
                                if service.localSort == mode {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(service.localSort == mode ? 0.08 : 0.001)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .frame(width: 160)
            }

            Button(action: { service.fetch_wallpapers() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .padding(10)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial.opacity(0.9))
                .overlay {
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(.primary.opacity(0.1), lineWidth: 0.5)
                }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private func show_settings() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.show_settings()
            return
        }

        let settingsView = SettingsView()
            .environmentObject(service)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        if let managerWindow = NSApp.keyWindow {
            let managerFrame = managerWindow.frame
            let settingsSize = window.frame.size
            let x = managerFrame.midX - settingsSize.width / 2
            let y = managerFrame.midY - settingsSize.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            window.center()
        }

        window.title = "Settings"
        window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: settingsView)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            if !service.isAtRoot {
                HStack {
                    Button(action: { service.back() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.left")
                            Text("Back")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 32)
                    .padding(.top, 16)

                    Spacer()
                }
            }

            ZStack {
                if service.isLoading {
                    loadingView
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.9)),
                            removal: .opacity.combined(with: .scale(scale: 1.1))
                        ))
                } else if service.wallpapers.isEmpty {
                    NoWpView
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity
                        ))
                } else {
                    gridView
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity
                        ))
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: service.isLoading)
        .animation(.easeInOut(duration: 0.4), value: service.wallpapers.isEmpty)
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 80, height: 80)
                    .overlay {
                        Circle()
                            .stroke(.primary.opacity(0.1), lineWidth: 1)
                    }

                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .primary.opacity(0.7)))
                    .scaleEffect(1.2)
            }

            VStack(spacing: 8) {
                Text(NSLocalizedString("loading_wallpapers", comment: "loading wallpapers"))
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.8))

                Text(NSLocalizedString("scanning_files", comment: "scanning for video files"))
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var NoWpView: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.primary.opacity(0.4))

            VStack(spacing: 8) {
                Text(NSLocalizedString("no_wallpapers_found", comment: "no wallpapers found"))
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.8))

                Text(NSLocalizedString("drop_files_or_add", comment: "drop files or add wallpaper"))
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("supported_formats", comment: "supported file formats"))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .onDrop(of: [.fileURL, .directory], isTargeted: $file_drag) { providers in
            drop_handle(providers)
        }
    }

    private var gridView: some View {
        ScrollView {
            let columns = [
                GridItem(.fixed(300), spacing: 30),
                GridItem(.fixed(300), spacing: 30),
                GridItem(.fixed(300), spacing: 30)
            ]

            LazyVGrid(columns: columns, alignment: .center, spacing: 30) {
                let displayed = showFavoritesOnly
                    ? service.wallpapers.filter { service.isFavorite($0) }
                    : service.wallpapers
                ForEach(Array(displayed.enumerated()), id: \.element.id) { index, wallpaper in
                    WallpaperCard(
                        wallpaper: wallpaper,
                        isActive: service.current_wp == wallpaper.path,
                        cardIsSelected: service.selected_wp?.id == wallpaper.id,
                        onSelect: {
                            withAnimation(.easeInOut(duration: 0.3)) { service.set_wp(wallpaper) }
                        },
                        onTap: {
                            if wallpaper.isFolder {
                                service.navigateTo(folder: wallpaper)
                            } else {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    if service.selected_wp?.id == wallpaper.id {
                                        service.select_wp(nil)
                                    } else {
                                        service.select_wp(wallpaper)
                                    }
                                }
                            }
                        },
                        onDelete: {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                delete_wp(wallpaper)
                                if service.selected_wp?.id == wallpaper.id { service.select_wp(nil) }
                            }
                        },
                        onRename: { rename_wp(wallpaper, to: $0) },
                        onExport: { export_wp(wallpaper) },
                        onQuickPreview: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                previewTarget = PreviewTarget(
                                    url: URL(fileURLWithPath: wallpaper.path),
                                    title: wallpaper.name,
                                    detail: ByteCountFormatter.string(fromByteCount: wallpaper.fileSize, countStyle: .file)
                                )
                            }
                        }
                    )
                    .environmentObject(service)
                    .frame(width: 300, height: 260)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.8).combined(with: .offset(y: 20))),
                        removal: .opacity.combined(with: .scale(scale: 0.8))
                    ))
                    .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.1), value: service.wallpapers.count)
                }
            }
            .padding(32)
        }
        .onDrop(of: [.fileURL, .directory], isTargeted: $file_drag) { providers in
            drop_handle(providers)
        }
    }

    private func drop_handle(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                DispatchQueue.main.async {
                    import_wp(from: url)
                }
            }
        }
        return true
    }

    private func import_wp(from url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        if !isDirectory.boolValue {
            let ext = url.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext) else { return }
        }

        let wp_storage_dir = macpaperService.wp_storage_dir

        do {
            try FileManager.default.createDirectory(at: wp_storage_dir, withIntermediateDirectories: true)
            let destination = wp_storage_dir.appendingPathComponent(url.lastPathComponent)

            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }

            if service.importMethod == .link {
                try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: url.resolvingSymlinksInPath())
            } else {
                try FileManager.default.copyItem(at: url, to: destination)
            }
            service.fetch_wallpapers()
        } catch {
            print(error)
        }
    }

    private func delete_wp(_ wallpaper: endup_wp) {
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: wallpaper.path), resultingItemURL: nil)
            service.fetch_wallpapers()
        } catch {
            print("while deleting wallpaper: \(error)")
        }
    }

    private func rename_wp(_ wallpaper: endup_wp, to newName: String) {
        let fileURL = URL(fileURLWithPath: wallpaper.path)
        let directory = fileURL.deletingLastPathComponent()
        let fileExtension = fileURL.pathExtension
        let newFileName = fileExtension.isEmpty ? newName : "\(newName).\(fileExtension)"
        let newURL = directory.appendingPathComponent(newFileName)

        do {
            try FileManager.default.moveItem(at: fileURL, to: newURL)
            service.fetch_wallpapers()
        } catch {
            print("Error renaming file: \(error)")
        }
    }

    private func export_wp(_ wallpaper: endup_wp) {
        let sourceURL = URL(fileURLWithPath: wallpaper.path)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }

        let fileExtension = sourceURL.pathExtension.lowercased()
        let isImage = ["jpg", "jpeg", "png", "gif"].contains(fileExtension)

        if isImage {
            ExportManager.shared.showExportMenu(
                for: wallpaper,
                sourceURL: sourceURL,
                showCropEditor: { image, wp, url in
                    self.showCropEditorWindow(image: image, wallpaper: wp, sourceURL: url)
                }
            )
        } else {
            ExportManager.shared.exportOriginal(wallpaper: wallpaper, sourceURL: sourceURL)
        }
    }

    private func showCropEditorWindow(image: NSImage, wallpaper: endup_wp, sourceURL: URL) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        let cropView = CropEditorView(
            image: image,
            wallpaperName: wallpaper.name,
            onCrop: { [weak window] cropRect, targetSize in
                window?.close()
                ExportManager.shared.exportWithCrop(
                    wallpaper: wallpaper,
                    sourceURL: sourceURL,
                    cropRect: cropRect,
                    targetSize: targetSize
                )
            },
            onCancel: { [weak window] in
                window?.close()
            }
        )

        window.center()
        window.title = NSLocalizedString("crop_editor_title", comment: "Crop Image")
        window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: cropView)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func isStillWallpaper(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png"].contains(ext)
    }
}
