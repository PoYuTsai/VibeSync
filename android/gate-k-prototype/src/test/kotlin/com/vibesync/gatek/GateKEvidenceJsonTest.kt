package com.vibesync.gatek

import org.junit.Assert.assertEquals
import org.junit.Test

class GateKEvidenceJsonTest {
    @Test
    fun `JSON evidence is deterministic and includes raw records before derived summary`() {
        val records = listOf(
            GateKTrialRecord(
                trialId = "trial-2",
                deviceClass = GateKDeviceClass.EMULATOR,
                apiLevel = 34,
                deviceModel = "pixel\"-api34",
                success = false,
                latencyMs = 4_000L,
                sessionOutcome = GateKSessionOutcome.ACCEPTED,
                dedupeOutcome = GateKDedupeOutcome.FIRST_SEEN,
            ),
            GateKTrialRecord(
                trialId = "trial-1",
                deviceClass = GateKDeviceClass.EMULATOR,
                apiLevel = 34,
                deviceModel = "pixel-api34",
                success = true,
                latencyMs = 100L,
                sessionOutcome = GateKSessionOutcome.ACCEPTED,
                dedupeOutcome = GateKDedupeOutcome.FIRST_SEEN,
            ),
        )

        val json = GateKEvidenceJson.encode(records)

        assertEquals(
            "{" +
                "\"schemaVersion\":1," +
                "\"trialRecords\":[" +
                "{\"trialId\":\"trial-1\",\"deviceClass\":\"EMULATOR\",\"apiLevel\":34," +
                "\"deviceModel\":\"pixel-api34\",\"reportedSuccess\":true,\"latencyMs\":100," +
                "\"sessionOutcome\":\"ACCEPTED\",\"dedupeOutcome\":\"FIRST_SEEN\"," +
                "\"attemptId\":\"trial-1\",\"sessionId\":\"session-trial-1\"," +
                "\"triggerElapsedRealtimeMs\":0,\"detectedElapsedRealtimeMs\":100," +
                "\"deviceDescriptor\":\"pixel-api34\",\"failureReason\":\"NONE\"," +
                "\"origin\":\"SYNTHETIC\"}," +
                "{\"trialId\":\"trial-2\",\"deviceClass\":\"EMULATOR\",\"apiLevel\":34," +
                "\"deviceModel\":\"pixel\\\"-api34\",\"reportedSuccess\":false,\"latencyMs\":4000," +
                "\"sessionOutcome\":\"ACCEPTED\",\"dedupeOutcome\":\"FIRST_SEEN\"," +
                "\"attemptId\":\"trial-2\",\"sessionId\":\"session-trial-2\"," +
                "\"triggerElapsedRealtimeMs\":0,\"detectedElapsedRealtimeMs\":4000," +
                "\"deviceDescriptor\":\"pixel\\\"-api34\",\"failureReason\":\"NONE\"," +
                "\"origin\":\"SYNTHETIC\"}" +
                "]," +
                "\"summary\":{\"totalTrials\":2,\"successfulTrials\":1,\"failedTrials\":1," +
                "\"successRate\":0.5,\"p50LatencyMs\":100,\"p95LatencyMs\":4000," +
                "\"minimumTrialsMet\":false,\"successRateMet\":false,\"latencyMet\":false," +
                "\"sessionContractMet\":true,\"dedupeContractMet\":true," +
                "\"runtimeOriginMet\":false," +
                "\"perEmulatorApiThresholdsMet\":false,\"dataIntegrityMet\":true," +
                "\"invalidRecordCount\":0,\"invalidTrialIds\":[],\"invalidAttemptIds\":[]," +
                "\"inconsistentSuccessTrialIds\":[]," +
                "\"emulatorApiSummaries\":{\"34\":{\"totalTrials\":2,\"successfulTrials\":1," +
                "\"failedTrials\":1,\"successRate\":0.5,\"p50LatencyMs\":100,\"p95LatencyMs\":4000," +
                "\"successRateMet\":false,\"latencyMet\":false}," +
                "\"35\":{\"totalTrials\":0,\"successfulTrials\":0,\"failedTrials\":0," +
                "\"successRate\":0.0,\"p50LatencyMs\":null,\"p95LatencyMs\":null," +
                "\"successRateMet\":false,\"latencyMet\":false}," +
                "\"36\":{\"totalTrials\":0,\"successfulTrials\":0,\"failedTrials\":0," +
                "\"successRate\":0.0,\"p50LatencyMs\":null,\"p95LatencyMs\":null," +
                "\"successRateMet\":false,\"latencyMet\":false}}," +
                "\"emulatorCandidate\":false,\"decision\":\"INCONCLUSIVE\"}}",
            json,
        )
    }

    @Test
    fun `JSON ignores a caller-forged derived summary and keeps raw records authoritative`() {
        val packet = GateKEvidenceAggregator().build(
            listOf(
                GateKTrialRecord(
                    trialId = "trial-1",
                    deviceClass = GateKDeviceClass.EMULATOR,
                    apiLevel = 34,
                    deviceModel = "pixel-api34",
                    success = true,
                    latencyMs = 100L,
                    sessionOutcome = GateKSessionOutcome.ACCEPTED,
                    dedupeOutcome = GateKDedupeOutcome.FIRST_SEEN,
                ),
            ),
        )
        val forged = packet.copy(
            summary = packet.summary.copy(
                successfulTrials = 999,
                successRate = 1.0,
                emulatorCandidate = true,
                decision = GateKDecision.EMULATOR_CANDIDATE,
            ),
        )

        assertEquals(GateKEvidenceJson.encode(packet), GateKEvidenceJson.encode(forged))
        assertEquals(1, GateKEvidenceAggregator().build(packet.trialRecords).summary.successfulTrials)
    }
}
