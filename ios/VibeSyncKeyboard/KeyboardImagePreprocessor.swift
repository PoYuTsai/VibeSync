import CryptoKit
import Foundation
import ImageIO
import UIKit

struct KeyboardPreparedImage: Equatable {
    let jpegData: Data
    let sha256: String
    let pixelWidth: Int
    let pixelHeight: Int
}

enum KeyboardImagePreprocessorError: Error, Equatable {
    case invalidImage
    case imageTooLarge
}

struct KeyboardImagePreprocessor {
    private let widths = [960, 768, 640]
    private let qualities: [CGFloat] = [0.82, 0.72, 0.62]

    func prepare(_ source: UIImage) throws -> KeyboardPreparedImage {
        guard source.size.width > 0,
              source.size.height > 0,
              source.cgImage != nil || source.ciImage != nil
        else {
            throw KeyboardImagePreprocessorError.invalidImage
        }

        for width in widths {
            let target = resized(source, maximumWidth: CGFloat(width))
            for quality in qualities {
                // jpegData rasterizes into a fresh container. The resulting
                // upload carries no original EXIF or GPS metadata.
                guard let data = target.jpegData(
                    compressionQuality: quality
                ) else {
                    continue
                }
                guard data.count <= KeyboardSharedConfig.maximumImageBytes
                else {
                    continue
                }
                let digest = SHA256.hash(data: data)
                    .map { String(format: "%02x", $0) }
                    .joined()
                return KeyboardPreparedImage(
                    jpegData: data,
                    sha256: digest,
                    pixelWidth: Int(target.size.width * target.scale),
                    pixelHeight: Int(target.size.height * target.scale)
                )
            }
        }
        throw KeyboardImagePreprocessorError.imageTooLarge
    }

    private func resized(
        _ image: UIImage,
        maximumWidth: CGFloat
    ) -> UIImage {
        let sourcePixelWidth = image.size.width * image.scale
        guard sourcePixelWidth > maximumWidth else { return image }
        let ratio = maximumWidth / sourcePixelWidth
        let targetSize = CGSize(
            width: maximumWidth,
            height: image.size.height * image.scale * ratio
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: targetSize,
            format: format
        )
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
