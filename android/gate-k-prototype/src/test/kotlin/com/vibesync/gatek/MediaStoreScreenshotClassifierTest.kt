package com.vibesync.gatek

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MediaStoreScreenshotClassifierTest {
    @Test
    fun `classifies an image under a MediaStore Screenshots path as a screenshot`() {
        val result = MediaStoreScreenshotClassifier.classify(
            MediaStoreImageMetadata(
                uri = "content://media/external/images/media/123",
                relativePath = "Pictures/Screenshots/",
                mimeType = "image/png",
            ),
        )

        assertEquals(
            MediaStoreScreenshotDecision.MediaStoreScreenshot,
            result,
        )
    }

    @Test
    fun `rejects a camera image even when it is a valid MediaStore image`() {
        val result = MediaStoreScreenshotClassifier.classify(
            MediaStoreImageMetadata(
                uri = "content://media/external/images/media/124",
                relativePath = "DCIM/Camera/",
                mimeType = "image/jpeg",
            ),
        )

        assertEquals(
            MediaStoreScreenshotDecision.Rejected(MediaStoreScreenshotRejectReason.NOT_SCREENSHOT_PATH),
            result,
        )
    }

    @Test
    fun `rejects non MediaStore authority and non image content`() {
        val wrongAuthority = MediaStoreScreenshotClassifier.classify(
            MediaStoreImageMetadata(
                uri = "content://com.example.photos/images/123",
                relativePath = "Pictures/Screenshots/",
                mimeType = "image/png",
            ),
        )
        val wrongMime = MediaStoreScreenshotClassifier.classify(
            MediaStoreImageMetadata(
                uri = "content://media/external/images/media/125",
                relativePath = "Pictures/Screenshots/",
                mimeType = "video/mp4",
            ),
        )

        assertTrue(wrongAuthority is MediaStoreScreenshotDecision.Rejected)
        assertEquals(
            MediaStoreScreenshotRejectReason.NOT_MEDIASTORE_URI,
            (wrongAuthority as MediaStoreScreenshotDecision.Rejected).reason,
        )
        assertEquals(
            MediaStoreScreenshotDecision.Rejected(MediaStoreScreenshotRejectReason.NOT_IMAGE),
            wrongMime,
        )
    }

    @Test
    fun `rejects path traversal and malformed screenshot metadata`() {
        val result = MediaStoreScreenshotClassifier.classify(
            MediaStoreImageMetadata(
                uri = "content://media/external/images/media/126",
                relativePath = "Pictures/../Screenshots/",
                mimeType = "image/png",
            ),
        )

        assertEquals(
            MediaStoreScreenshotDecision.Rejected(MediaStoreScreenshotRejectReason.INVALID_PATH),
            result,
        )
    }
}
