import Foundation
import Photos
import AppKit

struct PhotoAsset: Identifiable, Equatable {
    let id: String
    let phAsset: PHAsset
    var cachedThumbnail: NSImage?

    var creationDate: Date? {
        phAsset.creationDate
    }

    var pixelWidth: Int {
        phAsset.pixelWidth
    }

    var pixelHeight: Int {
        phAsset.pixelHeight
    }

    var isFavorite: Bool {
        phAsset.isFavorite
    }

    var isVideo: Bool {
        phAsset.mediaType == .video
    }

    var duration: TimeInterval {
        phAsset.duration
    }

    var formattedDuration: String {
        guard isVideo else { return "" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var aspectRatio: CGFloat {
        guard pixelHeight > 0 else { return 1.0 }
        return CGFloat(pixelWidth) / CGFloat(pixelHeight)
    }

    init(phAsset: PHAsset) {
        self.id = phAsset.localIdentifier
        self.phAsset = phAsset
    }

    static func == (lhs: PhotoAsset, rhs: PhotoAsset) -> Bool {
        lhs.id == rhs.id
    }
}
