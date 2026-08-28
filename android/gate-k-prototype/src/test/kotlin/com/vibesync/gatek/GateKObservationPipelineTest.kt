package com.vibesync.gatek

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GateKObservationPipelineTest {
    @Test
    fun `pipeline accepts one candidate during the visible session and ignores it after finish`() {
        val pipeline = GateKObservationPipeline()
        val started = pipeline.onImeShown(
            ImeSessionStart(sessionId = "session-1", imeShownAtEpochMs = 1_000L),
        )
        val candidate = ScreenshotCandidate(
            sessionId = "session-1",
            observedAtEpochMs = 1_001L,
            source = ScreenshotCandidateSource.MEDIA_STORE_SCREENSHOT,
            width = 1_080,
            height = 2_400,
            content = byteArrayOf(1, 2, 3),
        )

        assertTrue(started is ImeSessionStartResult.Started)
        assertEquals(
            GateKObservationResult.Accepted(
                CandidateIdentity("039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81"),
            ),
            pipeline.observe(candidate),
        )

        assertTrue(
            pipeline.onImeHidden(
                ImeSessionEnd(sessionId = "session-1", imeHiddenAtEpochMs = 2_000L),
            ) is ImeSessionEndResult.Ended,
        )
        assertEquals(
            GateKObservationResult.Ignored(IgnoredCandidateReason.NO_ACTIVE_SESSION),
            pipeline.observe(candidate.copy(observedAtEpochMs = 2_001L)),
        )
    }

    @Test
    fun `hiding clears dedupe so an equal-millisecond new session can accept again`() {
        val pipeline = GateKObservationPipeline()
        val candidate = ScreenshotCandidate(
            sessionId = "session-1",
            observedAtEpochMs = 2_001L,
            source = ScreenshotCandidateSource.MEDIA_STORE_SCREENSHOT,
            width = 1_080,
            height = 1_920,
            content = byteArrayOf(1, 2, 3),
        )

        assertTrue(
            pipeline.onImeShown(ImeSessionStart("session-1", 2_000L))
                is ImeSessionStartResult.Started,
        )
        assertTrue(pipeline.observe(candidate) is GateKObservationResult.Accepted)
        assertTrue(
            pipeline.onImeHidden(ImeSessionEnd("session-1", 2_000L))
                is ImeSessionEndResult.Ended,
        )
        assertTrue(
            pipeline.onImeShown(ImeSessionStart("session-2", 2_000L))
                is ImeSessionStartResult.Started,
        )

        assertTrue(
            pipeline.observe(candidate.copy(sessionId = "session-2", observedAtEpochMs = 2_002L))
                is GateKObservationResult.Accepted,
        )
    }

    @Test
    fun `normalized floor does not prevent hide from clearing the pipeline`() {
        val pipeline = GateKObservationPipeline()
        assertTrue(
            pipeline.onImeShown(ImeSessionStart("session-1", 2_000L))
                is ImeSessionStartResult.Started,
        )
        assertTrue(
            pipeline.onImeHidden(ImeSessionEnd("session-1", 2_000L))
                is ImeSessionEndResult.Ended,
        )
        assertTrue(
            pipeline.onImeShown(ImeSessionStart("session-2", 2_000L))
                is ImeSessionStartResult.Started,
        )

        assertTrue(
            pipeline.onImeHidden(ImeSessionEnd("session-2", 2_000L))
                is ImeSessionEndResult.Ended,
        )
        assertEquals(
            GateKObservationResult.Ignored(IgnoredCandidateReason.NO_ACTIVE_SESSION),
            pipeline.observe(
                ScreenshotCandidate(
                    sessionId = "session-2",
                    observedAtEpochMs = 2_002L,
                    source = ScreenshotCandidateSource.MEDIA_STORE_SCREENSHOT,
                    width = 1_080,
                    height = 1_920,
                    content = byteArrayOf(4, 5, 6),
                ),
            ),
        )
    }
}
