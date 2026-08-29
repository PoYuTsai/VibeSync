package com.vibesync.gatek

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CandidateIdentityTest {
    @Test
    fun `same content resent in one session is accepted once by public identity seam`() {
        val window = ImeSessionWindow(sessionId = "session-1", floorEpochMs = 1_000L)
        val firstCandidate = ScreenshotCandidate(
            sessionId = "session-1",
            observedAtEpochMs = 1_001L,
            source = ScreenshotCandidateSource.MEDIA_STORE_SCREENSHOT,
            width = 1_080,
            height = 2_400,
            content = byteArrayOf(1, 2, 3),
        )
        val resentCandidate = firstCandidate.copy(
            observedAtEpochMs = 1_002L,
            content = byteArrayOf(1, 2, 3),
        )
        val dedupe = ScreenshotCandidateDedupe()

        val first = dedupe.observe(window, firstCandidate)
        val duplicate = dedupe.observe(window, resentCandidate)

        assertTrue(first is CandidateIdentityDecision.FirstSeen)
        assertEquals(
            "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81",
            (first as CandidateIdentityDecision.FirstSeen).identity.sha256,
        )
        assertEquals(
            CandidateIdentityDecision.Duplicate(first.identity),
            duplicate,
        )
    }

    @Test
    fun `same content in a newer session gets a fresh session-scoped identity decision`() {
        val dedupe = ScreenshotCandidateDedupe()
        val firstWindow = ImeSessionWindow(sessionId = "session-1", floorEpochMs = 1_000L)
        val secondWindow = ImeSessionWindow(sessionId = "session-2", floorEpochMs = 2_000L)

        val first = dedupe.observe(firstWindow, candidate("session-1", 1_001L))
        val second = dedupe.observe(secondWindow, candidate("session-2", 2_001L))

        assertTrue(first is CandidateIdentityDecision.FirstSeen)
        assertTrue(second is CandidateIdentityDecision.FirstSeen)
        assertEquals(
            (first as CandidateIdentityDecision.FirstSeen).identity,
            (second as CandidateIdentityDecision.FirstSeen).identity,
        )
    }

    @Test
    fun `clear on hidden session permits an equal-millisecond new session`() {
        val dedupe = ScreenshotCandidateDedupe()
        val firstWindow = ImeSessionWindow(sessionId = "session-1", floorEpochMs = 2_000L)
        val secondWindow = ImeSessionWindow(sessionId = "session-2", floorEpochMs = 2_000L)

        assertTrue(
            dedupe.observe(firstWindow, candidate("session-1", 2_001L))
                is CandidateIdentityDecision.FirstSeen,
        )
        dedupe.clear()

        assertTrue(
            dedupe.observe(secondWindow, candidate("session-2", 2_001L))
                is CandidateIdentityDecision.FirstSeen,
        )
    }

    @Test
    fun `cancelled chunked identity preparation does not mutate dedupe`() {
        val dedupe = ScreenshotCandidateDedupe()
        val window = ImeSessionWindow(sessionId = "session-1", floorEpochMs = 3_000L)
        val content = ByteArray(128 * 1024) { (it and 0x7f).toByte() }
        var predicateChecks = 0

        val prepared = dedupe.prepareIdentity(content) {
            predicateChecks += 1
            predicateChecks < 3
        }

        assertNull(prepared)
        assertTrue("cancellation did not reach a later chunk", predicateChecks >= 3)
        assertTrue(
            dedupe.observe(
                window,
                candidate("session-1", 3_001L).copy(content = content),
            ) is CandidateIdentityDecision.FirstSeen,
        )
    }

    private fun candidate(sessionId: String, observedAtEpochMs: Long) = ScreenshotCandidate(
        sessionId = sessionId,
        observedAtEpochMs = observedAtEpochMs,
        source = ScreenshotCandidateSource.MEDIA_STORE_SCREENSHOT,
        width = 1_080,
        height = 2_400,
        content = byteArrayOf(1, 2, 3),
    )
}
