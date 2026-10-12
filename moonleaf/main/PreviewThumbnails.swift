//
//  PreviewThumbnails.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import SwiftUI
import AVFoundation

struct LazyImagePreview: View {
    let path: String
    var targetSize: NSSize = NSSize(width: 276, height: 184)
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: targetSize.width, maxHeight: targetSize.height)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.brown.opacity(0.3))
                    .onAppear {
                        loadThumbnail()
                    }
            }
        }
    }

    private func loadThumbnail() {
        if let cachedImage = ImageCache.shared.cachedThumbnail(forPath: path, size: targetSize) {
            self.image = cachedImage
            return
        }

        ImageCache.shared.loadThumbnail(forPath: path, size: targetSize) { generated in
            self.image = generated
        }
    }
}

struct videoPreview: View {
    let videoURL: URL
    var targetSize: NSSize = NSSize(width: 300, height: 200)
    @State private var thumbnail: NSImage?

    private static var loadingOperations = [String: Operation]()
    private static let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 3
        queue.qualityOfService = .utility
        return queue
    }()

    private var cacheKey: String {
        ImageCache.video.thumbnailKey(forPath: videoURL.path, size: targetSize)
    }

    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Rectangle()
                    .fill(Color.brown.opacity(0.3))
                    .overlay {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.7)))
                            .scaleEffect(0.8)
                    }
            }
        }
        .onAppear {
            loadThumbnail()
        }
        .onDisappear {
            cancelLoading()
        }
    }

    private func loadThumbnail() {
        let key = cacheKey
        if let cachedThumbnail = ImageCache.video.getImage(forKey: key) {
            self.thumbnail = cachedThumbnail
            return
        }

        cancelLoading()

        var operation: BlockOperation?
        operation = BlockOperation {
            if operation?.isCancelled ?? true { return }

            guard let nsImage = ImageCache.generateVideoThumbnail(forPath: self.videoURL.path, size: self.targetSize) else {
                DispatchQueue.main.async {
                    Self.loadingOperations.removeValue(forKey: key)
                }
                return
            }

            if operation?.isCancelled ?? true { return }

            ImageCache.video.setImage(nsImage, forKey: key)

            DispatchQueue.main.async {
                Self.loadingOperations.removeValue(forKey: key)
                if let op = operation, !op.isCancelled {
                    self.thumbnail = nsImage
                }
            }
        }

        if let op = operation {
            Self.loadingOperations[key] = op
            Self.operationQueue.addOperation(op)
        }
    }

    private func cancelLoading() {
        let key = cacheKey
        if let operation = Self.loadingOperations[key] {
            operation.cancel()
            Self.loadingOperations.removeValue(forKey: key)
        }
    }
}
