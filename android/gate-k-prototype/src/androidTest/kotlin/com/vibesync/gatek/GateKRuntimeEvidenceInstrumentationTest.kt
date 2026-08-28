package com.vibesync.gatek

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GateKRuntimeEvidenceInstrumentationTest {
    @Test
    fun `timeout and duplicate callback produce one runtime artifact`() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val store = GateKEvidenceStore(context.filesDir)
        val recorder = GateKTrialRecorder(
            deviceClass = GateKDeviceClass.EMULATOR,
            apiLevel = 34,
            deviceModel = "instrumentation-emulator",
        )
        val coordinator = GateKAttemptCoordinator()
        coordinator.onSessionShown("instrumentation-session")
        coordinator.markObserverReady("instrumentation-session")
        coordinator.begin(
            attemptId = GateKAttemptId("instrumentation-attempt"),
            sessionId = "instrumentation-session",
            monotonicStart = 20_000L,
        )

        val atDeadline = coordinator.timeout(
            attemptId = GateKAttemptId("instrumentation-attempt"),
            sessionId = "instrumentation-session",
            nowElapsedRealtimeMs = 23_000L,
        )
        assertEquals(GateKAttemptTerminalResult.WaitingForDeadline, atDeadline)
        val timeout = coordinator.timeout(
            attemptId = GateKAttemptId("instrumentation-attempt"),
            sessionId = "instrumentation-session",
            nowElapsedRealtimeMs = 23_001L,
        ) as GateKAttemptTerminalResult.Recorded
        assertEquals(
            GateKAttemptTerminalResult.IgnoredAlreadyTerminal,
            coordinator.detected(
                attemptId = GateKAttemptId("instrumentation-attempt"),
                sessionId = "instrumentation-session",
                detectedAtElapsedRealtimeMs = 23_100L,
                sessionOutcome = GateKSessionOutcome.ACCEPTED,
                dedupeOutcome = GateKDedupeOutcome.FIRST_SEEN,
            ),
        )
        recorder.recordTerminal(timeout.terminal)

        try {
            store.write(recorder.evidencePacket())
            val root = JSONObject(store.read().orEmpty())
            assertEquals(1, root.getInt("schemaVersion"))
            assertEquals(1, root.getJSONArray("trialRecords").length())
            val record = root.getJSONArray("trialRecords").getJSONObject(0)
            assertEquals("RUNTIME", record.getString("origin"))
            assertEquals("instrumentation-attempt", record.getString("attemptId"))
            assertEquals("instrumentation-session", record.getString("sessionId"))
            assertEquals("TIMEOUT", record.getString("failureReason"))
            assertTrue(record.has("triggerElapsedRealtimeMs"))
            assertTrue(record.has("detectedElapsedRealtimeMs"))
        } finally {
            store.evidenceFile.delete()
        }
    }
}
