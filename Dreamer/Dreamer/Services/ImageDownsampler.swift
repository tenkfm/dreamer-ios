import ImageIO
import UIKit

/// Decodes an image straight to the size it is shown at: a 1024 x 1536 dream image in a 56 pt
/// journal row is decoded at 168 px, not kept as a 6 MB bitmap.
enum ImageDownsampler {
    /// `pointSize`: the largest side on screen, in points.
    static func image(from data: Data, pointSize: CGFloat, scale: CGFloat = 3) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbnail = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, pointSize * scale)
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail) else { return nil }
        return UIImage(cgImage: image, scale: scale, orientation: .up)
    }

    /// The same, decoded off the main thread: tiles and rows ask for it as they scroll in, and
    /// decoding a JPEG there stalls the scroll for a frame each time.
    static func decoded(from data: Data, pointSize: CGFloat, scale: CGFloat = 3) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            image(from: data, pointSize: pointSize, scale: scale)
        }.value
    }
}
