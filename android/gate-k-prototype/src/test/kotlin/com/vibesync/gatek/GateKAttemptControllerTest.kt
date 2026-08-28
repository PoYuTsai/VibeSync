package com.vibesync.gatek

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GateKAttemptCoordinatorTest {
    @Test
    fun `attempt must start from a ready active session and latency excludes pre-tap wait`() {
        val controller = GateKAttemptCoordinator()

        assertEquals(
            GateKAttemptStartResult.RejectedObserverNotReady,
            controller.start(
                GateKAttemptStart(
                    attemptId = GateKAttemptId("attempt-before-ready"),
                    sessionId = "session-1",
                    triggeredAtElapsedRealtimeMs = 5_000L,
                ),
            ),
        )

        controller.onSessionShown("session-1")
        controller.markObserverReady("session-1")
        val started = controller.begin(
            attemptId = GateKAttemptId("attempt-1"),
            sessionId = "session-1",
            monotonicStart = 5_000L,
        )

        assertTrue(started is GateKAttemptStartResult.Started)
        val terminal = controller.detected(
            attemptId = GateKAttemptId("attempt-1"),
            sessionId = "session-1",
            detectedAtElapsedRealtimeMs = 5_100L,
            sessionOutcome = GateKSessionOutcome.ACCEPTED,
            dedupeOutcome = GateKDedupeOutcome.FIRST_SEEN,
        )

        assertTrue(terminal is GateKAttemptTerminalResult.Recorded)
        val recorded = (terminal as GateKAttemptTerminalResult.Recorded).terminal
        assertEquals(100L, recorded.latencyMs)
        assertEquals(5_000L, recorded.triggeredAtElapsedRealtimeMs)
        assertEquals(5_100L, recorded.detectedAtElapsedRealtimeMs)
        assertEquals(GateKAttemptState.SUCCEEDED, recorded.state)
    }

    @Test
    fun `one attempt has at most one terminal and duplicate callback adds no record`() {
        val controller = readyController()
        val started = controller.start(
            GateKAttemptStart(GateKAttemptId("attempt-1"), "session-1", 1_000L),
        )
        assertTrue(started is GateKAttemptStartResult.Started)

        val first = controller.detected(
            attemptId = GateKAttemptId("attempt-1"),
            sessionId = "session-1",
            detectedAtElapsedRealtimeMs = 1_100L,
            sessionOutcome = GateKSessionOutcome.ACCEPTED,
            dedupeOutcome = GateKDedupeOutcome.FIRST_SEEN,
        )
        val duplicate = controller.detected(
            attemptId = GateKAttemptId("attempt-1"),
            sessionId = "session-1",
            detectedAtElapsedRealtimeMs = 1_200L,
            sessionOutcome = GateKSessionOutcome.ACCEPTED,
            dedupeOutcome = GateKDedupeOutcome.DUPLICATE_SUPPRESSED,
        )

        assertTrue(first is GateKAttemptTerminalResult.Recorded)
        assertEquals(GateKAttemptTerminalResult.IgnoredAlreadyTerminal, duplicate)
        assertFalse(controller.hasActiveAttempt)
    }

    @Test
    fun `late detection terminalizes as one timeout and records a bounded failure reason`() {
        val controller = readyController()
        controller.start(GateKAttemptStart(GateKAttemptId("attempt-1"), "session-1", 2_000L))

        val waiting = controller.timeout(GateKAttemptId("attempt-1"), "session-1", 4_999L)
        val timedOut = controller.timeout(GateKAttemptId("attempt-1"), "session-1", 5_000L)
        val lateCallback = controller.detected(
            attemptId = GateKAttemptId("attempt-1"),
            sessionId = "session-1",
            detectedAtElapsedRealtimeMs = 5_100L,
            sessionOutcome = GateKSessionOutcome.ACCEPTED,
            dedupeOutcome = GateKDedupeOutcome.FIRST_SEEN,
        )

        assertEquals(GateKAttemptTerminalResult.WaitingForDeadline, waiting)
        assertTrue(timedOut is GateKAttemptTerminalResult.Recorded)
        assertEquals(
            GateKAttemptState.TIMED_OUT,
            (timedOut as GateKAttemptTerminalResult.Recorded).terminal.state,
        )
        assertEquals(
            GateKFailureReason.TIMEOUT,
            (timedOut as GateKAttemptTerminalResult.Recorded).terminal.failureReason,
        )
        assertEquals(GateKAttemptTerminalResult.IgnoredAlreadyTerminal, lateCallback)
    }

    @Test
    fun `observer or grant error without an active attempt creates no terminal`() {
        val controller = readyController()

        assertEquals(
            GateKAttemptTerminalResult.IgnoredNoActiveAttempt,
            controller.failed(
                attemptId = GateKAttemptId("none"),
                sessionId = "session-1",
                detectedAtElapsedRealtimeMs = 10L,
                reason = GateKFailureReason.QUERY_FAILED,
            ),
        )

        controller.start(GateKAttemptStart(GateKAttemptId("attempt-1"), "session-1", 100L))
        val failed = controller.failed(
            attemptId = GateKAttemptId("attempt-1"),
            sessionId = "session-1",
            detectedAtElapsedRealtimeMs = 150L,
            reason = GateKFailureReason.GRANT_UNAVAILABLE,
        )
        assertTrue(failed is GateKAttemptTerminalResult.Recorded)
        assertEquals(
            GateKAttemptState.FAILED,
            (failed as GateKAttemptTerminalResult.Recorded).terminal.state,
        )
        assertEquals(
            GateKFailureReason.GRANT_UNAVAILABLE,
            (failed as GateKAttemptTerminalResult.Recorded).terminal.failureReason,
        )
        assertEquals(
            GateKAttemptTerminalResult.IgnoredAlreadyTerminal,
            controller.failed(
                attemptId = GateKAttemptId("attempt-1"),
                sessionId = "session-1",
                detectedAtElapsedRealtimeMs = 160L,
                reason = GateKFailureReason.OBSERVER_ERROR,
            ),
        )
    }

    private fun readyController(): GateKAttemptCoordinator {
        val controller = GateKAttemptCoordinator()
        controller.onSessionShown("session-1")
        controller.markObserverReady("session-1")
        return controller
    }
}
