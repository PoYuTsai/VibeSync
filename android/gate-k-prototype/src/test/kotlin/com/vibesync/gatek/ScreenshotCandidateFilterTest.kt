package com.vibesync.gatek

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenshotCandidateFilterTest {
    @Test
    fun `accepts a MediaStore screenshot observed after the active session floor`() {
        val window = ImeSessionWindow(sessionId = "session-1", floorEpochMs = 1_000L)
        val candidate = ScreenshotCandidate(
            sessionId = "session-1",
            observedAtEpochMs = 1_001L,
            source = ScreenshotCandidateSource.MEDIA_STORE_SCREENSHOT,
            width = 1_080,
            height = 2_400,
            content = byteArrayOf(1, 2, 3),
        )

        val result = ScreenshotCandidateFilter.observe(window, candidate)

        assertTrue(result is ScreenshotObservationDecision.Accepted)
        assertEquals(candidate, (result as ScreenshotObservationDecision.Accepted).candidate)
    }

    @Test
    fun `ignores a screenshot at or before the session floor`() {
        val result = ScreenshotCandidateFilter.observe(
            ImeSessionWindow(sessionId = "session-1", floorEpochMs = 1_000L),
            ScreenshotCandidate(
                sessionId = "session-1",
                observedAtEpochMs = 1_000L,
                source = ScreenshotCandidateSource.MEDIA_STORE_SCREENSHOT,
                width = 1_080,
                height = 2_400,
                content = byteArrayOf(1),
            ),
        )

        assertEquals(
            ScreenshotObservationDecision.Ignored(IgnoredCandidateReason.BEFORE_SESSION_FLOOR),
            result,
        )
    }

    @Test
    fun `rejects a MediaStore image that is not identified as a screenshot`() {
        val result = ScreenshotCandidateFilter.observe(
            ImeSessionWindow(sessionId = "session-1", floorEpochMs = 1_000L),
            ScreenshotCandidate(
                sessionId = "session-1",
                observedAtEpochMs = 1_001L,
                source = ScreenshotCandidateSource.MEDIA_STORE_OTHER,
                width = 1_080,
                height = 2_400,
                content = byteArrayOf(1),
            ),
        )

        assertEquals(
            ScreenshotObservationDecision.Rejected(RejectedCandidateReason.UNSUPPORTED_SOURCE),
            result,
        )
    }

    @Test
    fun `ignores a screenshot from a different IME session`() {
        val result = ScreenshotCandidateFilter.observe(
            ImeSessionWindow(sessionId = "session-1", floorEpochMs = 1_000L),
            ScreenshotCandidate(
                sessionId = "session-2",
                observedAtEpochMs = 1_001L,
                source = ScreenshotCandidateSource.MEDIA_STORE_SCREENSHOT,
                width = 1_080,
                height = 2_400,
                content = byteArrayOf(1),
            ),
        )

        assertEquals(
            ScreenshotObservationDecision.Ignored(IgnoredCandidateReason.WRONG_SESSION),
            result,
        )
    }
}
