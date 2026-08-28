package com.vibesync.gatek

import org.junit.Assert.assertEquals
import org.junit.Test

class GateKAttemptArmFenceTest {
    @Test
    fun `attempt arm captures post-drain high water instead of cached fence`() {
        var currentFence = GateKMediaStoreAttemptFence(highWaterGeneration = 10L)
        val arm = GateKAttemptArmFence(
            drainRaceClosingDelta = {
                currentFence = GateKMediaStoreAttemptFence(highWaterGeneration = 11L)
                true
            },
            captureCurrentFence = { currentFence },
        )

        assertEquals(
            GateKMediaStoreAttemptFence(highWaterGeneration = 11L),
            arm.captureAfterDrain(),
        )
    }
}
