import Photos
import UIKit
import Observation

/// PhotoKit access shared by the Photos app and the photo widget.
@Observable
final class PhotoLibraryService {
    static let shared = PhotoLibraryService()

    private(set) var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    let imageManager = PHCachingImageManager()

    var canRead: Bool { status == .authorized || status == .limited }
    var isDenied: Bool { status == .denied || status == .restricted }

    @discardableResult
    func requestAccess() async -> Bool {
        if canRead { return true }
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return canRead
    }

    func refreshStatus() { status = PHPhotoLibrary.authorizationStatus(for: .readWrite) }

    func recentAssets(limit: Int = 0) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        if limit > 0 { options.fetchLimit = limit }
        return PHAsset.fetchAssets(with: options)
    }

    func albums() -> [PHAssetCollection] {
        var result: [PHAssetCollection] = []
        let smart = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil)
        smart.enumerateObjects { c, _, _ in result.append(c) }
        let user = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        user.enumerateObjects { c, _, _ in result.append(c) }
        return result
    }

    func image(for asset: PHAsset, size: CGSize, contentMode: PHImageContentMode = .aspectFill) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        return await withCheckedContinuation { cont in
            var resumed = false
            imageManager.requestImage(for: asset, targetSize: size, contentMode: contentMode, options: options) { img, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !degraded || img == nil {
                    guard !resumed else { return }
                    resumed = true
                    cont.resume(returning: img)
                }
            }
        }
    }

    /// Saves a captured image to the library (add-only permission is enough).
    func save(_ data: Data) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let req = PHAssetCreationRequest.forAsset()
            req.addResource(with: .photo, data: data, options: nil)
        }
    }
}
