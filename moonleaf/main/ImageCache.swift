//
//  ImageCache.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import AppKit
import AVFoundation

final class ImageCache {
    static let shared = ImageCache(countLimit: 60, totalCostLimit: 50 * 1024 * 1024)
    static let remote = ImageCache(countLimit: 100, totalCostLimit: 100 * 1024 * 1024)
    static let video = ImageCache(countLimit: 60, totalCostLimit: 40 * 1024 * 1024)

    private let cache = NSCache<NSString, NSImage>()
    private static let thumbnailQueue = DispatchQueue(
        label: "com.naomisphere.moonleaf.thumbnailQueue",
        qos: .utility,
        attributes: .concurrent
    )

    init(countLimit: Int = 60, totalCostLimit: Int = 50 * 1024 * 1024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    func getImage(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: NSImage, forKey key: String) {
        let cost = max(1, Int(image.size.width * image.size.height * 4))
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func clear() {
        cache.removeAllObjects()
    }

    func thumbnailKey(forPath path: String, size: NSSize) -> String {
        "\(path)#\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    func cachedThumbnail(forPath path: String, size: NSSize) -> NSImage? {
        getImage(forKey: thumbnailKey(forPath: path, size: size))
    }

    func loadThumbnail(
        forPath path: String,
        size: NSSize,
        completion: @escaping (NSImage?) -> Void
    ) {
        let key = thumbnailKey(forPath: path, size: size)
        if let cached = getImage(forKey: key) {
            if Thread.isMainThread {
                completion(cached)
            } else {
                DispatchQueue.main.async {
                    completion(cached)
                }
            }
            return
        }

        Self.thumbnailQueue.async { [weak self] in
            let ext = (path as NSString).pathExtension.lowercased()
            let generated: NSImage?
            if ["mp4", "mov"].contains(ext) {
                generated = Self.generateVideoThumbnail(forPath: path, size: size)
            } else {
                generated = Self.generateImageThumbnail(forPath: path, size: size)
            }

            if let generated = generated {
                self?.setImage(generated, forKey: key)
            }

            DispatchQueue.main.async {
                completion(generated)
            }
        }
    }

    static func generateImageThumbnail(forPath path: String, size: NSSize) -> NSImage? {
        guard let fullImage = NSImage(contentsOfFile: path) else { return nil }
        return resizeImageToFill(fullImage, to: size)
    }

    static func generateVideoThumbnail(forPath path: String, size: NSSize) -> NSImage? {
        let asset = AVAsset(url: URL(fileURLWithPath: path))
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: max(size.width * 2, 300), height: max(size.height * 2, 200))
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero

        let cgImage: CGImage
        if let firstTry = try? imageGenerator.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 60), actualTime: nil) {
            cgImage = firstTry
        } else {
            imageGenerator.requestedTimeToleranceAfter = .positiveInfinity
            imageGenerator.requestedTimeToleranceBefore = .positiveInfinity
            guard let fallback = try? imageGenerator.copyCGImage(at: .zero, actualTime: nil) else {
                return nil
            }
            cgImage = fallback
        }

        let rawImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return resizeImageToFill(rawImage, to: size)
    }

    static func resizeImageToFill(_ image: NSImage, to size: NSSize) -> NSImage {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0, size.width > 0, size.height > 0 else {
            return image
        }

        let widthRatio = size.width / imageSize.width
        let heightRatio = size.height / imageSize.height
        let scaleRatio = max(widthRatio, heightRatio)

        let scaledSize = NSSize(
            width: imageSize.width * scaleRatio,
            height: imageSize.height * scaleRatio
        )

        let drawingRect = NSRect(
            x: (size.width - scaledSize.width) / 2,
            y: (size.height - scaledSize.height) / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )

        let pixelWidth = max(1, Int(size.width.rounded()))
        let pixelHeight = max(1, Int(size.height.rounded()))
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let context = CGContext(
               data: nil,
               width: pixelWidth,
               height: pixelHeight,
               bitsPerComponent: 8,
               bytesPerRow: 0,
               space: CGColorSpaceCreateDeviceRGB(),
               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
           ) {
            context.interpolationQuality = .high
            context.draw(cgImage, in: drawingRect)
            if let outputCG = context.makeImage() {
                return NSImage(cgImage: outputCG, size: size)
            }
        }

        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(
            in: drawingRect,
            from: NSRect(origin: .zero, size: imageSize),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()
        return newImage
    }
}
