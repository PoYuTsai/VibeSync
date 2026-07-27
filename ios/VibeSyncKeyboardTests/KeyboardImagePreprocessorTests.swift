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
