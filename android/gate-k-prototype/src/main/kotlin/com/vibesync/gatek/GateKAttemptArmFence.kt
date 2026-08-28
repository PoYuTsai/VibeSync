package com.vibesync.gatek

/**
 * Public ordering seam for arming an attempt. The caller must finish its
 * bounded, worker-serialized race-closing drain before reading the fence.
 */
class GateKAttemptArmFence(
    private val drainRaceClosingDelta: () -> Boolean,
    private val captureCurrentFence: () -> GateKMediaStoreAttemptFence?,
) {
    fun captureAfterDrain(): GateKMediaStoreAttemptFence? =
        if (drainRaceClosingDelta()) captureCurrentFence() else null
}
