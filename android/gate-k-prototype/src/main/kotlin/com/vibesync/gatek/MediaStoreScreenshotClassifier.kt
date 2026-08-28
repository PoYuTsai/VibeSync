package com.vibesync.gatek

import java.net.URI

data class MediaStoreImageMetadata(
    val uri: String,
    val relativePath: String?,
    val mimeType: String?,
    val width: Int = 0,
    val height: Int = 0,
    val observedAtEpochMs: Long = 0L,
)

sealed interface MediaStoreScreenshotDecision {
    data object MediaStoreScreenshot : MediaStoreScreenshotDecision

    data class Rejected(val reason: MediaStoreScreenshotRejectReason) :
        MediaStoreScreenshotDecision
}

enum class MediaStoreScreenshotRejectReason {
    NOT_MEDIASTORE_URI,
    NOT_IMAGE,
    INVALID_PATH,
    NOT_SCREENSHOT_PATH,
}

/**
 * Classifies screenshot provenance from authoritative MediaStore metadata.
 * Callers cannot opt into the screenshot source by setting a boolean.
 */
object MediaStoreScreenshotClassifier {
    fun classify(metadata: MediaStoreImageMetadata): MediaStoreScreenshotDecision {
        val parsedUri = try {
            URI(metadata.uri)
        } catch (_: IllegalArgumentException) {
            return MediaStoreScreenshotDecision.Rejected(
                MediaStoreScreenshotRejectReason.NOT_MEDIASTORE_URI,
            )
        }
        val authority = parsedUri.rawAuthority?.lowercase()
        val rawPath = parsedUri.rawPath.orEmpty()
        val decodedPath = parsedUri.path.orEmpty()
        if (parsedUri.scheme?.lowercase() != "content"
            || authority != "media"
            || !isMediaStoreImagePath(decodedPath)
            || rawPath.contains('\\')
            || rawPath.contains("..")
            || decodedPath.contains("..")
        ) {
            return MediaStoreScreenshotDecision.Rejected(
                MediaStoreScreenshotRejectReason.NOT_MEDIASTORE_URI,
            )
        }
        val mimeType = metadata.mimeType?.trim()?.lowercase()
        if (mimeType.isNullOrBlank() || !mimeType.startsWith("image/")) {
            return MediaStoreScreenshotDecision.Rejected(
                MediaStoreScreenshotRejectReason.NOT_IMAGE,
            )
        }
        val relativePath = metadata.relativePath?.trim()
        if (relativePath.isNullOrBlank()
            || relativePath.contains('\\')
            || relativePath.contains("..")
            || relativePath.split('/').dropLast(1).any(String::isBlank)
        ) {
            return MediaStoreScreenshotDecision.Rejected(
                MediaStoreScreenshotRejectReason.INVALID_PATH,
            )
        }
        val pathSegments = relativePath
            .trimEnd('/')
            .split('/')
            .filter(String::isNotBlank)
        if (pathSegments.none { it.equals("screenshots", ignoreCase = true) }) {
            return MediaStoreScreenshotDecision.Rejected(
                MediaStoreScreenshotRejectReason.NOT_SCREENSHOT_PATH,
            )
        }
        return MediaStoreScreenshotDecision.MediaStoreScreenshot
    }

    private fun isMediaStoreImagePath(path: String): Boolean {
        val segments = path.split('/').filter(String::isNotBlank)
        if (segments.size < 4) return false
        val imagesIndex = segments.indexOfLast { it.equals("images", ignoreCase = true) }
        val mediaIndex = segments.indexOfLast { it.equals("media", ignoreCase = true) }
        return imagesIndex >= 0
            && mediaIndex == imagesIndex + 1
            && mediaIndex < segments.lastIndex
            && segments.last().isNotBlank()
    }
}
