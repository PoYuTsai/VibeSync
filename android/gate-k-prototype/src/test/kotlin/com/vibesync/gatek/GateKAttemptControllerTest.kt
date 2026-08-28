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
    fun `detection at exactly three seconds is still a successful observation`() {
        val controller = readyController()
        controller.start(GateKAttemptStart(GateKAttemptId("attempt-deadline"), "session-1", 1_000L))

        val terminal = controller.detected(
            attemptId = GateKAttemptId("attempt-deadline"),
            sessionId = "session-1",
            detectedAtElapsedRealtimeMs = 4_000L,
            sessionOutcome = GateKSessionOutcome.ACCEPTED,
            dedupeOutcome = GateKDedupeOutcome.FIRST_SEEN,
        ) as GateKAttemptTerminalResult.Recorded

        assertEquals(3_000L, terminal.terminal.latencyMs)
        assertEquals(GateKAttemptState.SUCCEEDED, terminal.terminal.state)
        assertEquals(GateKFailureReason.NONE, terminal.terminal.failureReason)
    }

    @Test
    fun `late detection terminalizes as one timeout and records a bounded failure reason`() {
        val controller = readyController()
        controller.start(GateKAttemptStart(GateKAttemptId("attempt-1"), "session-1", 2_000L))

        val waiting = controller.timeout(GateKAttemptId("attempt-1"), "session-1", 4_999L)
        val atDeadline = controller.timeout(GateKAttemptId("attempt-1"), "session-1", 5_000L)
        val timedOut = controller.timeout(GateKAttemptId("attempt-1"), "session-1", 5_001L)
        val lateCallback = controller.detected(
            attemptId = GateKAttemptId("attempt-1"),
            sessionId = "session-1",
            detectedAtElapsedRealtimeMs = 5_100L,
            sessionOutcome = GateKSessionOutcome.ACCEPTED,
            dedupeOutcome = GateKDedupeOutcome.FIRST_SEEN,
        )

        assertEquals(GateKAttemptTerminalResult.WaitingForDeadline, waiting)
        assertEquals(GateKAttemptTerminalResult.WaitingForDeadline, atDeadline)
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

    @Test
    fun `timed out attempt late candidate cannot terminate the next fenced attempt`() {
        val controller = readyController()
        val fence = GateKMediaStoreAttemptFence(highWaterGeneration = 10L)
        controller.begin(
            attemptId = GateKAttemptId("attempt-a"),
            sessionId = "session-1",
            monotonicStart = 1_000L,
            mediaStoreFence = fence,
        )

        assertTrue(
            controller.timeout(
                attemptId = GateKAttemptId("attempt-a"),
                sessionId = "session-1",
                nowElapsedRealtimeMs = 4_001L,
            ) is GateKAttemptTerminalResult.Recorded,
        )
        val started = controller.begin(
            attemptId = GateKAttemptId("attempt-b"),
            sessionId = "session-1",
            monotonicStart = 4_010L,
            mediaStoreFence = fence,
        )
        assertTrue(started is GateKAttemptStartResult.Started)

        val lateCandidate = controller.detected(
            attemptId = GateKAttemptId("attempt-b"),
            sessionId = "session-1",
            detectedAtElapsedRealtimeMs = 4_100L,
            sessionOutcome = GateKSessionOutcome.ACCEPTED,
            dedupeOutcome = GateKDedupeOutcome.FIRST_SEEN,
            candidateIdentity = GateKMediaStoreCandidateIdentity(
                mediaId = "a-row",
                generation = 10L,
            ),
        )

        assertFalse(
            controller.isCandidateEligible(
                GateKMediaStoreCandidateIdentity("a-row", generation = 10L),
            ),
        )
        assertEquals(GateKAttemptTerminalResult.IgnoredStaleObservation, lateCandidate)
        assertTrue(controller.hasActiveAttempt)

        assertTrue(
            controller.isCandidateEligible(
                GateKMediaStoreCandidateIdentity("b-row", generation = 11L),
            ),
        )

        val freshCandidate = controller.detected(
            attemptId = GateKAttemptId("attempt-b"),
            sessionId = "session-1",
            detectedAtElapsedRealtimeMs = 4_100L,
            sessionOutcome = GateKSessionOutcome.ACCEPTED,
            dedupeOutcome = GateKDedupeOutcome.FIRST_SEEN,
            candidateIdentity = GateKMediaStoreCandidateIdentity(
                mediaId = "b-row",
                generation = 11L,
            ),
        )
        assertTrue(freshCandidate is GateKAttemptTerminalResult.Recorded)
    }

    private fun readyController(): GateKAttemptCoordinator {
        val controller = GateKAttemptCoordinator()
        controller.onSessionShown("session-1")
        controller.markObserverReady("session-1")
        return controller
    }
}
