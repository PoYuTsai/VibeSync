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
}
