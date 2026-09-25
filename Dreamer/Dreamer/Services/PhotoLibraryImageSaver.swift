import Photos
import UIKit

enum ImageSavingError: Error {
    case imageNotFound
    case accessDenied
}

/// Adds a dream image to Photos (add-only permission): the downloaded file, or an asset in mock mode.
struct PhotoLibraryImageSaver: ImageSaving {
    func saveImage(named assetName: String) async throws {
        guard let data = UIImage(named: assetName)?.jpegData(compressionQuality: 0.95) else {
            throw ImageSavingError.imageNotFound
        }
        try await saveImage(data: data)
    }

    func saveImage(data: Data) async throws {
        guard UIImage(data: data) != nil else { throw ImageSavingError.imageNotFound }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw ImageSavingError.accessDenied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
        }
    }
}
