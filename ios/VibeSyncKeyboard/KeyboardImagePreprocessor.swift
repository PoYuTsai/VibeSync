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

    /// The user screenshots while our own keyboard covers the bottom of the
    /// screen, so the raw capture contains our panel — including the candidate
    /// replies we produced a moment earlier. Uploading that wastes budget,
    /// dilutes the chat text once the image is downscaled, and lets the
    /// compiler transcribe our own suggestions as if they were chat messages.
    /// Removing the overlay before hashing keeps the upload, its SHA-256 and
    /// the on-screen preview describing exactly the same bytes.
    static func croppingBottom(
        _ image: UIImage,
        fraction: CGFloat
    ) -> UIImage {
        guard fraction > 0.01,
              fraction < 0.95,
              image.imageOrientation == .up,
              let cgImage = image.cgImage
        else {
            return image
        }
        let pixelHeight = CGFloat(cgImage.height)
        let keptHeight = (pixelHeight * (1 - fraction)).rounded(.down)
        guard keptHeight >= 64,
              let cropped = cgImage.cropping(
                  to: CGRect(
                      x: 0,
                      y: 0,
                      width: CGFloat(cgImage.width),
                      height: keptHeight
                  )
              )
        else {
            return image
        }
        return UIImage(
            cgImage: cropped,
            scale: image.scale,
            orientation: .up
        )
    }

    func prepare(_ source: UIImage) throws -> KeyboardPreparedImage {
        try prepare(source, croppingBottomFraction: 0)
    }

    func prepare(
        _ source: UIImage,
        croppingBottomFraction fraction: CGFloat
    ) throws -> KeyboardPreparedImage {
        guard source.size.width > 0,
              source.size.height > 0,
              source.cgImage != nil || source.ciImage != nil
        else {
            throw KeyboardImagePreprocessorError.invalidImage
        }
        let trimmed = Self.croppingBottom(source, fraction: fraction)

        for width in widths {
            let target = resized(trimmed, maximumWidth: CGFloat(width))
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
