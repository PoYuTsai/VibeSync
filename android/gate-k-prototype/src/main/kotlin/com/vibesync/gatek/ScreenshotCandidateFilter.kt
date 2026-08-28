package com.vibesync.gatek

enum class ScreenshotCandidateSource {
    MEDIA_STORE_SCREENSHOT,
    MEDIA_STORE_OTHER,
    UNKNOWN,
}

/** A transient observation; callers must not persist its image bytes. */
data class ScreenshotCandidate(
    val sessionId: String,
    val observedAtEpochMs: Long,
    val source: ScreenshotCandidateSource,
    val width: Int,
    val height: Int,
    val content: ByteArray,
)

sealed interface ScreenshotObservationDecision {
    data class Accepted(val candidate: ScreenshotCandidate) : ScreenshotObservationDecision

    data class Ignored(val reason: IgnoredCandidateReason) : ScreenshotObservationDecision

    data class Rejected(val reason: RejectedCandidateReason) : ScreenshotObservationDecision
}

enum class IgnoredCandidateReason {
    NO_ACTIVE_SESSION,
    WRONG_SESSION,
    BEFORE_SESSION_FLOOR,
}

enum class RejectedCandidateReason {
    UNSUPPORTED_SOURCE,
    INVALID_DIMENSIONS,
    EMPTY_CONTENT,
}

/**
 * Fail-closed candidate metadata gate. It has no Android or storage
 * dependency, so the public behavior is deterministic on every host.
 */
object ScreenshotCandidateFilter {
    fun observe(
        window: ImeSessionWindow?,
        candidate: ScreenshotCandidate,
    ): ScreenshotObservationDecision {
        if (candidate.source != ScreenshotCandidateSource.MEDIA_STORE_SCREENSHOT) {
            return ScreenshotObservationDecision.Rejected(
                RejectedCandidateReason.UNSUPPORTED_SOURCE,
            )
        }
        if (candidate.width <= 0 || candidate.height <= 0) {
            return ScreenshotObservationDecision.Rejected(
                RejectedCandidateReason.INVALID_DIMENSIONS,
            )
        }
        if (candidate.content.isEmpty()) {
            return ScreenshotObservationDecision.Rejected(
                RejectedCandidateReason.EMPTY_CONTENT,
            )
        }
        if (window == null) {
            return ScreenshotObservationDecision.Ignored(IgnoredCandidateReason.NO_ACTIVE_SESSION)
        }
        if (candidate.sessionId != window.sessionId) {
            return ScreenshotObservationDecision.Ignored(IgnoredCandidateReason.WRONG_SESSION)
        }
        if (candidate.observedAtEpochMs <= window.floorEpochMs) {
            return ScreenshotObservationDecision.Ignored(
                IgnoredCandidateReason.BEFORE_SESSION_FLOOR,
            )
        }
        return ScreenshotObservationDecision.Accepted(candidate)
    }
}
