package com.vibesync.gatek

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ImeSessionFloorTest {
    @Test
    fun `starting and ending an IME session exposes a monotonic public floor`() {
        val floor = ImeSessionFloor()

        val first = floor.start(
            ImeSessionStart(sessionId = "session-1", imeShownAtEpochMs = 1_000L),
        )

        assertTrue(first is ImeSessionStartResult.Started)
        assertEquals(
            ImeSessionWindow(
                sessionId = "session-1",
                floorEpochMs = 1_000L,
            ),
            (first as ImeSessionStartResult.Started).window,
        )
        assertEquals(
            ImeSessionWindow(
                sessionId = "session-1",
                floorEpochMs = 1_000L,
            ),
            floor.current,
        )

        val ended = floor.end(
            ImeSessionEnd(sessionId = "session-1", imeHiddenAtEpochMs = 2_000L),
        )

        assertTrue(ended is ImeSessionEndResult.Ended)
        assertNull(floor.current)

        val staleRestart = floor.start(
            ImeSessionStart(sessionId = "session-2", imeShownAtEpochMs = 999L),
        )

        assertEquals(ImeSessionStartResult.RejectedNonMonotonicFloor, staleRestart)
        assertNull(floor.current)
    }
}
