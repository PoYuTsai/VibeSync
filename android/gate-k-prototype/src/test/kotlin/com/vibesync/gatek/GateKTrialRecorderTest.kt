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

        assertEquals("MEDIASTORE_GRANT_REVOKED", recorded.failureReason)
        assertEquals(0, recorder.evidencePacket().summary.successfulTrials)
        assertTrue(recorder.evidenceJson().contains("MEDIASTORE_GRANT_REVOKED"))
    }
}
