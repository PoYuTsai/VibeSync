package com.vibesync.gatek

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GateKEvidenceAggregatorTest {
    @Test
    fun `summary counts raw records and computes deterministic nearest-rank latency`() {
        val records = listOf(
            trial(trialId = "trial-3", latencyMs = 400L, success = false),
            trial(trialId = "trial-1", latencyMs = 100L, success = true),
            trial(trialId = "trial-2", latencyMs = 200L, success = true),
        )

        val packet = GateKEvidenceAggregator().build(records)

        assertEquals(records, packet.trialRecords)
        assertEquals(3, packet.summary.totalTrials)
        assertEquals(2, packet.summary.successfulTrials)
        assertEquals(1, packet.summary.failedTrials)
        assertEquals(2.0 / 3.0, packet.summary.successRate, 0.000_001)
        assertEquals(200L, packet.summary.p50LatencyMs)
        assertEquals(400L, packet.summary.p95LatencyMs)
        assertFalse(packet.summary.emulatorCandidate)
        assertEquals(GateKDecision.INCONCLUSIVE, packet.summary.decision)
    }

    @Test
    fun `forty successful trials on each required emulator API produce only an emulator candidate`() {
        val records = listOf(34, 35, 36).flatMap { apiLevel ->
            (1..40).map { index ->
                GateKTrialRecord(
                    trialId = "api-$apiLevel-trial-$index",
                    deviceClass = GateKDeviceClass.EMULATOR,
                    apiLevel = apiLevel,
                    deviceModel = "emulator-$apiLevel",
                    success = true,
                    latencyMs = 100L,
                    sessionOutcome = GateKSessionOutcome.ACCEPTED,
                    dedupeOutcome = GateKDedupeOutcome.FIRST_SEEN,
                )
            }
        }

        val summary = GateKEvidenceAggregator().build(records).summary

        assertTrue(summary.minimumTrialsMet)
        assertTrue(summary.successRateMet)
        assertTrue(summary.latencyMet)
        assertTrue(summary.emulatorCandidate)
        assertEquals(GateKDecision.EMULATOR_CANDIDATE, summary.decision)
    }

    @Test
    fun `reported success cannot pass a rejected session or unevaluated dedupe`() {
        val records = listOf(
            trial(
                trialId = "rejected",
                latencyMs = 100L,
                success = true,
                sessionOutcome = GateKSessionOutcome.REJECTED,
            ),
            trial(
                trialId = "not-evaluated",
                latencyMs = 100L,
                success = true,
                dedupeOutcome = GateKDedupeOutcome.NOT_EVALUATED,
            ),
        )

        val summary = GateKEvidenceAggregator().build(records).summary

        assertEquals(0, summary.successfulTrials)
        assertFalse(summary.dedupeContractMet)
        assertFalse(summary.emulatorCandidate)
    }

    @Test
    fun `reported failure cannot hide an otherwise verifiable success`() {
        val summary = GateKEvidenceAggregator().build(
            listOf(
                trial(
                    trialId = "mismatch",
                    latencyMs = 100L,
                    success = false,
                ),
            ),
        ).summary

        assertEquals(0, summary.successfulTrials)
        assertFalse(summary.dataIntegrityMet)
        assertEquals(listOf("mismatch"), summary.inconsistentSuccessTrialIds)
    }

    @Test
    fun `negative latency blank trial id and duplicate ids fail data integrity closed`() {
        val records = listOf(
            trial(trialId = "bad-latency", latencyMs = -1L, success = true),
            trial(trialId = "", latencyMs = 100L, success = true),
            trial(trialId = "duplicate", latencyMs = 100L, success = true),
            trial(trialId = "duplicate", latencyMs = 100L, success = true),
        )

        val summary = GateKEvidenceAggregator().build(records).summary

        assertFalse(summary.dataIntegrityMet)
        assertEquals(4, summary.invalidRecordCount)
        assertFalse(summary.emulatorCandidate)
    }

    @Test
    fun `one emulator API failing its own threshold cannot be washed out by other APIs`() {
        val records = listOf(34, 35, 36).flatMap { apiLevel ->
            (1..40).map { index ->
                GateKTrialRecord(
                    trialId = "api-$apiLevel-trial-$index",
                    deviceClass = GateKDeviceClass.EMULATOR,
                    apiLevel = apiLevel,
                    deviceModel = "emulator-$apiLevel",
                    success = !(apiLevel == 35 && index <= 3),
                    latencyMs = if (apiLevel == 35 && index <= 3) 4_000L else 100L,
                    sessionOutcome = GateKSessionOutcome.ACCEPTED,
                    dedupeOutcome = GateKDedupeOutcome.FIRST_SEEN,
                )
            }
        }

        val summary = GateKEvidenceAggregator().build(records).summary

        assertTrue(summary.successRateMet)
        assertFalse(summary.perEmulatorApiThresholdsMet)
        assertFalse(summary.emulatorCandidate)
    }

    private fun trial(
        trialId: String,
        latencyMs: Long,
        success: Boolean,
        sessionOutcome: GateKSessionOutcome = GateKSessionOutcome.ACCEPTED,
        dedupeOutcome: GateKDedupeOutcome = GateKDedupeOutcome.FIRST_SEEN,
    ) = GateKTrialRecord(
        trialId = trialId,
        deviceClass = GateKDeviceClass.EMULATOR,
        apiLevel = 34,
        deviceModel = "test-emulator",
        success = success,
        latencyMs = latencyMs,
        sessionOutcome = sessionOutcome,
        dedupeOutcome = dedupeOutcome,
    )
}
