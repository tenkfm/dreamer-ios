import Foundation
import Testing
import UIKit
@testable import Dreamer

struct ImageDownsamplerTests {
    private func jpeg(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test func aDreamImageIsDecodedAtRowSize() throws {
        let image = try #require(ImageDownsampler.image(from: jpeg(width: 1024, height: 1536), pointSize: 56))
        let cgImage = try #require(image.cgImage)
        // 56 pt at 3x: the long side is 168 px, not 1536.
        #expect(max(cgImage.width, cgImage.height) == 168)
        #expect(image.scale == 3)
    }

    @Test func aSmallImageIsNotBlownUp() throws {
        let image = try #require(ImageDownsampler.image(from: jpeg(width: 100, height: 100), pointSize: 200))
        #expect(try #require(image.cgImage).width == 100)
    }

    @Test func garbageGivesNothing() {
        #expect(ImageDownsampler.image(from: Data("not an image".utf8), pointSize: 56) == nil)
    }
}
