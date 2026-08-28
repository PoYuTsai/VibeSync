package com.vibesync.gatek

/**
 * Public lifecycle event emitted when the prototype IME becomes visible.
 *
 * Epoch milliseconds are supplied by the host so the contract stays
 * deterministic in tests and does not need a clock dependency.
 */
data class ImeSessionStart(
    val sessionId: String,
    val imeShownAtEpochMs: Long,
)

/** Public lifecycle event emitted when the prototype IME is hidden. */
data class ImeSessionEnd(
    val sessionId: String,
    val imeHiddenAtEpochMs: Long,
)

/** The only session state exposed to candidate observers. */
data class ImeSessionWindow(
    val sessionId: String,
    val floorEpochMs: Long,
)

sealed interface ImeSessionStartResult {
    data class Started(val window: ImeSessionWindow) : ImeSessionStartResult

    data object RejectedInvalidEvent : ImeSessionStartResult

    data object RejectedActiveSession : ImeSessionStartResult

    data object RejectedNonMonotonicFloor : ImeSessionStartResult
}

sealed interface ImeSessionEndResult {
    data class Ended(val window: ImeSessionWindow) : ImeSessionEndResult

    data object RejectedInvalidEvent : ImeSessionEndResult

    data object RejectedUnknownSession : ImeSessionEndResult

    data object RejectedOutOfOrder : ImeSessionEndResult
}

/**
 * Tracks the currently visible IME session and its monotonic observation
 * floor. The class keeps no screenshot or chat data.
 */
class ImeSessionFloor {
    private var lastFloorEpochMs: Long? = null
    private var activeWindow: ImeSessionWindow? = null

    val current: ImeSessionWindow?
        get() = activeWindow

    fun start(event: ImeSessionStart): ImeSessionStartResult {
        if (event.sessionId.isBlank() || event.imeShownAtEpochMs < 0L) {
            return ImeSessionStartResult.RejectedInvalidEvent
        }
        if (activeWindow != null) {
            return ImeSessionStartResult.RejectedActiveSession
        }
        val previousFloor = lastFloorEpochMs
        if (previousFloor != null && event.imeShownAtEpochMs < previousFloor) {
            return ImeSessionStartResult.RejectedNonMonotonicFloor
        }
        if (previousFloor == Long.MAX_VALUE) {
            return ImeSessionStartResult.RejectedNonMonotonicFloor
        }
        val floorEpochMs = when {
            previousFloor == null -> event.imeShownAtEpochMs
            event.imeShownAtEpochMs == previousFloor ->
                previousFloor + 1L

            else -> event.imeShownAtEpochMs
        }

        val window = ImeSessionWindow(
            sessionId = event.sessionId,
            floorEpochMs = floorEpochMs,
        )
        lastFloorEpochMs = floorEpochMs
        activeWindow = window
        return ImeSessionStartResult.Started(window)
    }

    fun end(event: ImeSessionEnd): ImeSessionEndResult {
        if (event.sessionId.isBlank() || event.imeHiddenAtEpochMs < 0L) {
            return ImeSessionEndResult.RejectedInvalidEvent
        }
        val window = activeWindow ?: return ImeSessionEndResult.RejectedUnknownSession
        if (event.sessionId != window.sessionId) {
            return ImeSessionEndResult.RejectedUnknownSession
        }
        // A normalized same-millisecond floor can be one millisecond ahead
        // of the real wall clock. Hiding the IME must still terminate the
        // active window so the pipeline and session-scoped dedupe are cleared.
        if (event.imeHiddenAtEpochMs < window.floorEpochMs
            && window.floorEpochMs - event.imeHiddenAtEpochMs > 1L
        ) {
            return ImeSessionEndResult.RejectedOutOfOrder
        }
        activeWindow = null
        return ImeSessionEndResult.Ended(window)
    }
}
