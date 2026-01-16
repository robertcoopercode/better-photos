import Foundation
import Photos

struct Album: Identifiable {
    let id: String
    let title: String
    let count: Int
    let collection: PHAssetCollection

    var icon: String {
        switch collection.assetCollectionSubtype {
        case .smartAlbumUserLibrary:
            return "photo.on.rectangle"
        case .smartAlbumFavorites:
            return "heart.fill"
        case .smartAlbumScreenshots:
            return "camera.viewfinder"
        case .smartAlbumSelfPortraits:
            return "person.crop.square"
        case .smartAlbumPanoramas:
            return "pano"
        case .smartAlbumVideos:
            return "video"
        case .smartAlbumLivePhotos:
            return "livephoto"
        case .smartAlbumRecentlyAdded:
            return "clock"
        default:
            return "photo.stack"
        }
    }

    init(collection: PHAssetCollection) {
        self.id = collection.localIdentifier
        self.title = collection.localizedTitle ?? "Untitled"
        self.collection = collection

        // Get photo and video count
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        self.count = assets.count
    }
}

// MARK: - Folder Hierarchy Support

/// Represents a folder that can contain albums or other folders
struct Folder: Identifiable {
    let id: String
    let title: String
    let collectionList: PHCollectionList
    var children: [SidebarItem]

    init(collectionList: PHCollectionList, children: [SidebarItem] = []) {
        self.id = collectionList.localIdentifier
        self.title = collectionList.localizedTitle ?? "Untitled Folder"
        self.collectionList = collectionList
        self.children = children
    }

    /// Total count of items in all nested albums
    var totalCount: Int {
        children.reduce(0) { total, item in
            switch item {
            case .album(let album):
                return total + album.count
            case .folder(let folder):
                return total + folder.totalCount
            }
        }
    }
}

/// Represents either an album or a folder in the sidebar
enum SidebarItem: Identifiable {
    case album(Album)
    case folder(Folder)

    var id: String {
        switch self {
        case .album(let album):
            return "album-\(album.id)"
        case .folder(let folder):
            return "folder-\(folder.id)"
        }
    }

    var title: String {
        switch self {
        case .album(let album):
            return album.title
        case .folder(let folder):
            return folder.title
        }
    }
}
