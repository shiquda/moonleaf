//
//  ExportManager.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import AppKit
import UniformTypeIdentifiers

class ExportManager: NSObject {
    static let shared = ExportManager()

    private var currentWallpaper: endup_wp?
    private var currentSourceURL: URL?
    private var onShowCropEditor: ((NSImage, endup_wp, URL) -> Void)?

    private override init() {
        super.init()
    }

    private func getExportFolder() -> URL {
        MoonleafConfigStore.shared.exportFolderURL()
    }

    func showExportMenu(
        for wallpaper: endup_wp,
        sourceURL: URL,
        showCropEditor: @escaping (NSImage, endup_wp, URL) -> Void
    ) {
        self.currentWallpaper = wallpaper
        self.currentSourceURL = sourceURL
        self.onShowCropEditor = showCropEditor

        let menu = NSMenu()

        let originalItem = NSMenuItem(
            title: NSLocalizedString("export_original", comment: "Original Size"),
            action: #selector(handleExportOriginal),
            keyEquivalent: ""
        )
        originalItem.target = self
        menu.addItem(originalItem)

        menu.addItem(NSMenuItem.separator())

        let customItem = NSMenuItem(
            title: NSLocalizedString("download_custom_ratio", comment: "Custom Aspect Ratio"),
            action: #selector(handleExportCustom),
            keyEquivalent: ""
        )
        customItem.target = self
        menu.addItem(customItem)

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func handleExportOriginal() {
        guard let wallpaper = currentWallpaper, let sourceURL = currentSourceURL else { return }
        exportOriginal(wallpaper: wallpaper, sourceURL: sourceURL)
    }

    @objc private func handleExportCustom() {
        guard let wallpaper = currentWallpaper,
              let sourceURL = currentSourceURL,
              let showCropEditor = onShowCropEditor,
              let image = NSImage(contentsOfFile: sourceURL.path) else { return }
        showCropEditor(image, wallpaper, sourceURL)
    }

    func exportOriginal(wallpaper: endup_wp, sourceURL: URL) {
        let fileExtension = sourceURL.pathExtension.lowercased()
        var allowedTypes: [UTType] = []

        switch fileExtension {
        case "jpg", "jpeg": allowedTypes = [.jpeg]
        case "png": allowedTypes = [.png]
        case "gif": allowedTypes = [.gif]
        case "mp4": allowedTypes = [.mpeg4Movie]
        case "mov": allowedTypes = [.quickTimeMovie]
        default: allowedTypes = [.jpeg, .png, .gif, .mpeg4Movie, .quickTimeMovie]
        }

        NSApp.activate(ignoringOtherApps: true)

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = allowedTypes
        savePanel.nameFieldStringValue = wallpaper.name
        savePanel.title = NSLocalizedString("export_wallpaper", comment: "Export Wallpaper")
        savePanel.directoryURL = getExportFolder()

        savePanel.begin { response in
            if response == .OK, let destinationURL = savePanel.url {
                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                } catch {
                    self.showError(error.localizedDescription)
                }
            }

            AppDelegate.updateActivationPolicy()
        }
    }

    func exportWithCrop(wallpaper: endup_wp, sourceURL: URL, cropRect: CGRect, targetSize: NSSize) {
        guard let sourceImage = NSImage(contentsOfFile: sourceURL.path) else { return }

        let croppedImage = cropImage(sourceImage, cropRect: cropRect, targetSize: targetSize)

        NSApp.activate(ignoringOtherApps: true)

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg]
        savePanel.nameFieldStringValue = "\(wallpaper.name)_\(Int(targetSize.width))x\(Int(targetSize.height))"
        savePanel.title = NSLocalizedString("export_wallpaper", comment: "Export Wallpaper")
        savePanel.directoryURL = getExportFolder()

        savePanel.begin { response in
            if response == .OK, let destinationURL = savePanel.url {
                self.saveCroppedImage(croppedImage, to: destinationURL)
            }

            AppDelegate.updateActivationPolicy()
        }
    }

    private func cropImage(_ image: NSImage, cropRect: CGRect, targetSize: NSSize) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let croppedCGImage = cgImage.cropping(to: cropRect),
              let context = CGContext(
                  data: nil,
                  width: Int(targetSize.width),
                  height: Int(targetSize.height),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(croppedCGImage, in: CGRect(origin: .zero, size: targetSize))

        guard let finalCGImage = context.makeImage() else { return image }
        return NSImage(cgImage: finalCGImage, size: targetSize)
    }

    private func saveCroppedImage(_ image: NSImage, to destinationURL: URL) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            showError("Could not convert image")
            return
        }

        let fileExtension = destinationURL.pathExtension.lowercased()
        let imageData = fileExtension == "png"
            ? bitmapImage.representation(using: .png, properties: [:])
            : bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.95])

        guard let data = imageData else {
            showError("Could not create image data")
            return
        }

        do {
            try data.write(to: destinationURL)
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("export_error", comment: "Export Error")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
