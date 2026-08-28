package com.vibesync.gatek

import java.nio.file.Files
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GateKEvidenceStoreTest {
    @Test
    fun `runtime terminal is exported atomically as bounded metadata JSON`() {
        val directory = Files.createTempDirectory("gate-k-evidence-test").toFile()
        try {
            val recorder = GateKTrialRecorder(
                deviceClass = GateKDeviceClass.EMULATOR,
                apiLevel = 34,
                deviceModel = "emulator-api34",
                rawDeviceDescriptor = GateKDeviceDescriptor(
                    manufacturer = "Google",
                    brand = "google",
                    model = "sdk_gphone64_x86_64",
                    product = "sdk_gphone64_x86_64",
                    fingerprint = "generic/sdk/emulator",
                    apiLevel = 34,
                ),
            )
            val coordinator = GateKAttemptCoordinator()
            coordinator.onSessionShown("session-1")
            coordinator.markObserverReady("session-1")
            coordinator.begin(
                attemptId = GateKAttemptId("attempt-1"),
                sessionId = "session-1",
                monotonicStart = 10_000L,
            )
            val terminal = coordinator.detected(
                attemptId = GateKAttemptId("attempt-1"),
                sessionId = "session-1",
                detectedAtElapsedRealtimeMs = 10_100L,
                sessionOutcome = GateKSessionOutcome.ACCEPTED,
                dedupeOutcome = GateKDedupeOutcome.FIRST_SEEN,
            ) as GateKAttemptTerminalResult.Recorded
            recorder.recordTerminal(terminal.terminal)

            val store = GateKEvidenceStore(directory)
            val file = store.write(recorder.evidencePacket())
            val json = store.read().orEmpty()

            assertTrue(file.name == GateKEvidenceStore.FILE_NAME)
            assertTrue(json.contains("\"schemaVersion\":1"))
            assertTrue(json.contains("\"origin\":\"RUNTIME\""))
            assertTrue(json.contains("\"attemptId\":\"attempt-1\""))
            assertTrue(json.contains("\"sessionId\":\"session-1\""))
            assertTrue(json.contains("\"triggerElapsedRealtimeMs\":10000"))
            assertTrue(json.contains("\"detectedElapsedRealtimeMs\":10100"))
            assertFalse(json.contains("imageBytes"))
            assertFalse(java.io.File(directory, ".gate-k-evidence.json.tmp").exists())
        } finally {
            directory.deleteRecursively()
        }
    }
}
