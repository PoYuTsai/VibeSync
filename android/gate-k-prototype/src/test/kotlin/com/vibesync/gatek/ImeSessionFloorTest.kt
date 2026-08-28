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

    @Test
    fun `same millisecond is a valid new session with a strictly higher floor`() {
        val floor = ImeSessionFloor()
        assertTrue(
            floor.start(ImeSessionStart("session-1", 2_000L))
                is ImeSessionStartResult.Started,
        )
        assertTrue(
            floor.end(ImeSessionEnd("session-1", 2_000L))
                is ImeSessionEndResult.Ended,
        )

        val second = floor.start(ImeSessionStart("session-2", 2_000L))
        assertTrue(second is ImeSessionStartResult.Started)
        assertEquals(2_001L, (second as ImeSessionStartResult.Started).window.floorEpochMs)
        assertTrue(
            floor.end(ImeSessionEnd("session-2", 2_000L))
                is ImeSessionEndResult.Ended,
        )
        assertNull(floor.current)
        assertEquals(
            ImeSessionStartResult.RejectedNonMonotonicFloor,
            floor.start(ImeSessionStart("session-3", 1_999L)),
        )
    }

    @Test
    fun `grossly out of order hidden event is rejected while one millisecond skew ends session`() {
        val floor = ImeSessionFloor()
        floor.start(ImeSessionStart("session-1", 2_000L))
        floor.end(ImeSessionEnd("session-1", 2_000L))
        floor.start(ImeSessionStart("session-2", 2_000L))

        assertEquals(
            ImeSessionEndResult.RejectedOutOfOrder,
            floor.end(ImeSessionEnd("session-2", 1_998L)),
        )
        assertEquals("session-2", floor.current?.sessionId)
        assertTrue(
            floor.end(ImeSessionEnd("session-2", 2_000L))
                is ImeSessionEndResult.Ended,
        )
        assertNull(floor.current)
    }
}
