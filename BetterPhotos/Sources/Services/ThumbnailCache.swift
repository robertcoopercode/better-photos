import Foundation
import Photos
import AppKit

actor ThumbnailCache {
    private let cache = NSCache<NSString, NSImage>()
    private let cachingManager = PHCachingImageManager()
    private var prefetchedAssets: Set<String> = []

    init() {
        cache.countLimit = 500  // Keep 500 thumbnails in memory
        cache.totalCostLimit = 100 * 1024 * 1024  // 100MB limit
    }

    func thumbnail(for asset: PHAsset, size: CGSize) async -> NSImage? {
        let key = "\(asset.localIdentifier)-\(Int(size.width))" as NSString

        // Check cache first
        if let cached = cache.object(forKey: key) {
            return cached
        }

        // Load and cache
        let image = await loadThumbnail(asset: asset, size: size)
        if let image = image {
            cache.setObject(image, forKey: key)
        }
        return image
    }

    func prefetchThumbnails(for assets: [PHAsset], size: CGSize) {
        let newAssets = assets.filter { !prefetchedAssets.contains($0.localIdentifier) }
        guard !newAssets.isEmpty else { return }

        cachingManager.startCachingImages(
            for: newAssets,
            targetSize: size,
            contentMode: .aspectFill,
            options: nil
        )

        for asset in newAssets {
            prefetchedAssets.insert(asset.localIdentifier)
        }
    }

    func stopPrefetching(for assets: [PHAsset], size: CGSize) {
        cachingManager.stopCachingImages(
            for: assets,
            targetSize: size,
            contentMode: .aspectFill,
            options: nil
        )

        for asset in assets {
            prefetchedAssets.remove(asset.localIdentifier)
        }
    }

    func clearCache() {
        cache.removeAllObjects()
        cachingManager.stopCachingImagesForAllAssets()
        prefetchedAssets.removeAll()
    }

    private func loadThumbnail(asset: PHAsset, size: CGSize) async -> NSImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true

            cachingManager.requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    continuation.resume(returning: image)
                }
            }
        }
    }
}
