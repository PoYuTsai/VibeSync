package com.vibesync.gatek

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GateKTrialRecorderTest {
    @Test
    fun `recorder preserves raw trial metadata and derives a deterministic packet`() {
        val recorder = GateKTrialRecorder(
            deviceClass = GateKDeviceClass.UNCLASSIFIED,
            apiLevel = 34,
            deviceModel = "prototype-device",
        )

        val recorded = recorder.record(
            success = true,
            latencyMs = 125L,
            sessionOutcome = GateKSessionOutcome.ACCEPTED,
            dedupeOutcome = GateKDedupeOutcome.FIRST_SEEN,
        )

        assertEquals("trial-1", recorded.trialId)
        assertEquals(listOf(recorded), recorder.records)
        assertEquals(1, recorder.evidencePacket().summary.totalTrials)
        assertTrue(recorder.evidenceJson().contains("\"reportedSuccess\":true"))
    }

    @Test
    fun `recorder fail-closed result retains failure reason without image bytes`() {
        val recorder = GateKTrialRecorder(
            deviceClass = GateKDeviceClass.UNCLASSIFIED,
            apiLevel = 34,
            deviceModel = "prototype-device",
        )

        val recorded = recorder.record(
            success = false,
            latencyMs = 3_001L,
            sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
            dedupeOutcome = GateKDedupeOutcome.NOT_EVALUATED,
            failureReason = "MEDIASTORE_GRANT_REVOKED",
        )

        assertEquals(GateKFailureReason.GRANT_UNAVAILABLE, recorded.failureReason)
        assertEquals(0, recorder.evidencePacket().summary.successfulTrials)
        assertTrue(recorder.evidenceJson().contains("GRANT_UNAVAILABLE"))
    }

    @Test
    fun `runtime terminal exports attempt binding and bounded metadata only`() {
        val recorder = GateKTrialRecorder(
            deviceClass = GateKDeviceClass.EMULATOR,
            apiLevel = 34,
            deviceModel = "emulator-api34",
        )
        val coordinator = GateKAttemptCoordinator()
        coordinator.onSessionShown("session-runtime")
        coordinator.markObserverReady("session-runtime")
        assertTrue(
            coordinator.begin(
                attemptId = GateKAttemptId("attempt-runtime"),
                sessionId = "session-runtime",
                monotonicStart = 10_000L,
            ) is GateKAttemptStartResult.Started,
        )

        val terminal = coordinator.detected(
            attemptId = GateKAttemptId("attempt-runtime"),
            sessionId = "session-runtime",
            detectedAtElapsedRealtimeMs = 10_125L,
            sessionOutcome = GateKSessionOutcome.ACCEPTED,
            dedupeOutcome = GateKDedupeOutcome.FIRST_SEEN,
        ) as GateKAttemptTerminalResult.Recorded
        val record = recorder.recordTerminal(terminal.terminal)

        assertEquals("attempt-runtime", record.attemptId)
        assertEquals("session-runtime", record.sessionId)
        assertEquals(10_000L, record.triggerElapsedRealtimeMs)
        assertEquals(10_125L, record.detectedElapsedRealtimeMs)
        assertEquals(125L, record.latencyMs)
        assertEquals(GateKTrialOrigin.RUNTIME, record.origin)
        assertEquals(GateKFailureReason.NONE, record.failureReason)
        assertTrue(!recorder.evidenceJson().contains("imageBytes"))
    }
}
