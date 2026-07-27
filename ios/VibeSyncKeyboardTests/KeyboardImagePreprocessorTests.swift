import UIKit
import XCTest

final class KeyboardImagePreprocessorTests: XCTestCase {
    func testRasterReencodeProducesBoundedJPEGAndDigest() throws {
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 1_200, height: 2_400)
        )
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(
                CGRect(x: 0, y: 0, width: 1_200, height: 2_400)
            )
            UIColor.black.setFill()
            context.fill(
                CGRect(x: 100, y: 100, width: 800, height: 80)
            )
        }

        let prepared = try KeyboardImagePreprocessor().prepare(image)

        XCTAssertLessThanOrEqual(
            prepared.jpegData.count,
            KeyboardSharedConfig.maximumImageBytes
        )
        XCTAssertLessThanOrEqual(prepared.pixelWidth, 960)
        XCTAssertEqual(prepared.sha256.count, 64)
        XCTAssertEqual(
            Array(prepared.jpegData.prefix(2)),
            [0xff, 0xd8]
        )
    }

    func testOverlayFractionTrimsOurOwnKeyboardBeforeHashing() throws {
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 600, height: 1_000)
        )
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 1_000))
        }

        let full = try KeyboardImagePreprocessor().prepare(
            image,
            croppingBottomFraction: 0
        )
        let trimmed = try KeyboardImagePreprocessor().prepare(
            image,
            croppingBottomFraction: 0.4
        )

        XCTAssertEqual(trimmed.pixelWidth, full.pixelWidth)
        XCTAssertLessThan(trimmed.pixelHeight, full.pixelHeight)
        XCTAssertNotEqual(trimmed.sha256, full.sha256)
    }

    func testOutOfRangeOverlayFractionLeavesTheCaptureIntact() throws {
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 600, height: 1_000)
        )
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 1_000))
        }

        let baseline = try KeyboardImagePreprocessor().prepare(image)
        for fraction in [CGFloat(0), 0.005, 0.99, -1] {
            let prepared = try KeyboardImagePreprocessor().prepare(
                image,
                croppingBottomFraction: fraction
            )
            XCTAssertEqual(prepared.sha256, baseline.sha256)
        }
    }

    func testEmptyImageIsRejectedBeforeUpload() {
        XCTAssertThrowsError(
            try KeyboardImagePreprocessor().prepare(UIImage())
        ) {
            XCTAssertEqual(
                $0 as? KeyboardImagePreprocessorError,
                .invalidImage
            )
        }
    }
}
