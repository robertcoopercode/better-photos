import Photos
import AppKit

class PhotoLibraryService {
    private let imageManager = PHCachingImageManager()
    private let databaseService = PhotosDatabaseService()

    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    func fetchAllPhotos() async throws -> [PhotoAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false
        // Fetch both images and videos
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                         PHAssetMediaType.image.rawValue,
                                         PHAssetMediaType.video.rawValue)

        let results = PHAsset.fetchAssets(with: options)

        var assets: [PhotoAsset] = []
        assets.reserveCapacity(results.count)

        results.enumerateObjects { asset, _, _ in
            assets.append(PhotoAsset(phAsset: asset))
        }

        return assets
    }

    func fetchPhotosFromAlbum(_ album: Album) async throws -> [PhotoAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let results = PHAsset.fetchAssets(in: album.collection, options: options)

        var assets: [PhotoAsset] = []
        assets.reserveCapacity(results.count)

        results.enumerateObjects { asset, _, _ in
            // Include both images and videos
            if asset.mediaType == .image || asset.mediaType == .video {
                assets.append(PhotoAsset(phAsset: asset))
            }
        }

        return assets
    }

    func fetchPhotosByKeyword(_ keyword: String) async throws -> [PhotoAsset] {
        // Get UUIDs of photos/videos with this keyword from the database
        let uuids = databaseService.getPhotoUUIDsWithKeyword(keyword)

        guard !uuids.isEmpty else {
            return []
        }

        // Convert UUIDs to local identifiers (PhotoKit format: "UUID/L0/001")
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                         PHAssetMediaType.image.rawValue,
                                         PHAssetMediaType.video.rawValue)

        let allResults = PHAsset.fetchAssets(with: options)

        // Create a set of UUIDs for fast lookup (case-insensitive)
        let uuidSet = Set(uuids.map { $0.uppercased() })

        var assets: [PhotoAsset] = []

        allResults.enumerateObjects { asset, _, _ in
            let assetUUID = (asset.localIdentifier.components(separatedBy: "/").first ?? "").uppercased()
            if uuidSet.contains(assetUUID) {
                assets.append(PhotoAsset(phAsset: asset))
            }
        }

        return assets
    }

    func fetchAlbums() async -> [Album] {
        var albums: [Album] = []

        // Fetch user albums
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )

        userAlbums.enumerateObjects { collection, _, _ in
            let album = Album(collection: collection)
            if album.count > 0 {
                albums.append(album)
            }
        }

        // Sort by title
        albums.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        return albums
    }

    /// Fetches albums and folders in hierarchical structure (matching Photos.app sidebar)
    func fetchAlbumHierarchy() async -> [SidebarItem] {
        var items: [SidebarItem] = []

        // Fetch top-level user collections (both folders and albums)
        let topLevel = PHCollectionList.fetchTopLevelUserCollections(with: nil)

        topLevel.enumerateObjects { collection, _, _ in
            if let folder = collection as? PHCollectionList {
                // This is a folder - recursively fetch its contents
                let folderItem = self.buildFolder(folder)
                // Only include folders that have content
                if !folderItem.children.isEmpty {
                    items.append(.folder(folderItem))
                }
            } else if let albumCollection = collection as? PHAssetCollection {
                // This is an album at the top level
                let album = Album(collection: albumCollection)
                if album.count > 0 {
                    items.append(.album(album))
                }
            }
        }

        return items
    }

    /// Recursively builds a Folder with its nested albums and subfolders
    private func buildFolder(_ collectionList: PHCollectionList) -> Folder {
        var children: [SidebarItem] = []

        let contents = PHCollection.fetchCollections(in: collectionList, options: nil)

        contents.enumerateObjects { collection, _, _ in
            if let subfolder = collection as? PHCollectionList {
                // Nested folder
                let subfolderItem = self.buildFolder(subfolder)
                if !subfolderItem.children.isEmpty {
                    children.append(.folder(subfolderItem))
                }
            } else if let albumCollection = collection as? PHAssetCollection {
                // Album inside folder
                let album = Album(collection: albumCollection)
                if album.count > 0 {
                    children.append(.album(album))
                }
            }
        }

        return Folder(collectionList: collectionList, children: children)
    }

    func loadThumbnail(for asset: PHAsset, targetSize: CGSize) async -> NSImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            options.isSynchronous = false

            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // Check if this is the final result (not a degraded preview)
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded || image != nil {
                    continuation.resume(returning: image)
                }
            }
        }
    }

    func loadFullImage(for asset: PHAsset, maxDimension: CGFloat = 2048) async throws -> NSImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            // Calculate target size maintaining aspect ratio
            let aspectRatio = CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
            let targetSize: CGSize
            if aspectRatio > 1 {
                targetSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
            } else {
                targetSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
            }

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    func startCaching(assets: [PHAsset], targetSize: CGSize) {
        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: nil
        )
    }

    func stopCaching(assets: [PHAsset], targetSize: CGSize) {
        imageManager.stopCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: nil
        )
    }

    func stopAllCaching() {
        imageManager.stopCachingImagesForAllAssets()
    }

    func deletePhotos(_ assets: [PHAsset]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
        }
    }

    /// Fetches all albums containing the specified photo asset
    func fetchAlbumsContaining(asset: PHAsset) async -> [Album] {
        var containingAlbums: [Album] = []

        // Fetch all user albums
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )

        userAlbums.enumerateObjects { collection, _, _ in
            // Check if this album contains the asset
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "localIdentifier == %@", asset.localIdentifier)
            let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)

            if assets.count > 0 {
                containingAlbums.append(Album(collection: collection))
            }
        }

        return containingAlbums
    }

    /// Returns the total count of all photos and videos in the library
    func getTotalPhotoCount() async -> Int {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        // Count both images and videos
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                         PHAssetMediaType.image.rawValue,
                                         PHAssetMediaType.video.rawValue)
        let results = PHAsset.fetchAssets(with: options)
        return results.count
    }
}
