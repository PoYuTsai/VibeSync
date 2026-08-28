package com.vibesync.gatek

/** Stable public identity for one user-triggered or measured attempt. */
@JvmInline
value class GateKAttemptId(val value: String)

enum class GateKAttemptState {
    ACTIVE,
    SUCCEEDED,
    FAILED,
    TIMED_OUT,
}

/** Bounded failure vocabulary; raw exception/message text never enters evidence. */
enum class GateKFailureReason {
    NONE,
    TIMEOUT,
    SESSION_ENDED,
    GRANT_UNAVAILABLE,
    OBSERVER_ERROR,
    QUERY_FAILED,
    CONTENT_UNAVAILABLE,
    UNVERIFIED_OUTCOME,
    INVALID_EVENT,
    INVALID_TIMING,
    DUPLICATE_CALLBACK,
    DUPLICATE_ATTEMPT,
    METADATA_REJECTED,
    GENERATION_OVERFLOW,
    HASH_ERROR;

    companion object {
        /** Maps legacy runtime labels into the bounded evidence vocabulary. */
        fun fromLegacy(value: String?): GateKFailureReason = when {
            value == null -> NONE
            value == "FULL_IMAGE_GRANT_UNAVAILABLE" -> GRANT_UNAVAILABLE
            value == "MEDIASTORE_GRANT_REVOKED" -> GRANT_UNAVAILABLE
            value == "MEDIASTORE_OBSERVER_REGISTRATION_FAILED" -> OBSERVER_ERROR
            value == "MEDIASTORE_QUERY_FAILED" -> QUERY_FAILED
            value == "MEDIA_STORE_VERSION_UNAVAILABLE" -> OBSERVER_ERROR
            value == "MEDIA_STORE_VERSION_CHANGED" -> OBSERVER_ERROR
            value == "CONTENT_UNAVAILABLE" -> CONTENT_UNAVAILABLE
            value == "DUPLICATE_SUPPRESSED" -> DUPLICATE_CALLBACK
            value == "OBSERVATION_LATENCY_INVALID_OR_OVER_3S" -> TIMEOUT
            value.startsWith("IGNORED_") || value.startsWith("REJECTED_") -> METADATA_REJECTED
            else -> INVALID_EVENT
        }
    }
}

data class GateKAttemptStart(
    val attemptId: GateKAttemptId,
    val sessionId: String,
    val triggeredAtElapsedRealtimeMs: Long,
)

data class GateKActiveAttempt(
    val attemptId: GateKAttemptId,
    val sessionId: String,
    val triggeredAtElapsedRealtimeMs: Long,
)

data class GateKAttemptTerminal(
    val attemptId: GateKAttemptId,
    val sessionId: String,
    val state: GateKAttemptState,
    val triggeredAtElapsedRealtimeMs: Long,
    val detectedAtElapsedRealtimeMs: Long,
    val latencyMs: Long,
    val sessionOutcome: GateKSessionOutcome,
    val dedupeOutcome: GateKDedupeOutcome,
    val failureReason: GateKFailureReason,
)

sealed interface GateKAttemptStartResult {
    data class Started(val attempt: GateKActiveAttempt) : GateKAttemptStartResult

    data object RejectedInvalidEvent : GateKAttemptStartResult

    data object RejectedNoActiveSession : GateKAttemptStartResult

    data object RejectedObserverNotReady : GateKAttemptStartResult

    data object RejectedWrongSession : GateKAttemptStartResult

    data object RejectedActiveAttempt : GateKAttemptStartResult

    data object RejectedDuplicateAttemptId : GateKAttemptStartResult
}

sealed interface GateKAttemptTerminalResult {
    data class Recorded(val terminal: GateKAttemptTerminal) : GateKAttemptTerminalResult

    data object WaitingForDeadline : GateKAttemptTerminalResult

    data object IgnoredAlreadyTerminal : GateKAttemptTerminalResult

    data object IgnoredNoActiveAttempt : GateKAttemptTerminalResult

    data object IgnoredWrongAttempt : GateKAttemptTerminalResult

    data object IgnoredWrongSession : GateKAttemptTerminalResult

    data object RejectedInvalidTiming : GateKAttemptTerminalResult
}

/**
 * Serializes one attempt at a time. Observer callbacks and runtime errors can
 * only terminalize an already-started attempt; they can never create a trial
 * on their own or create a second terminal outcome.
 */
class GateKAttemptCoordinator(
    private val maxObservationLatencyMs: Long = DEFAULT_MAX_ATTEMPT_LATENCY_MS,
) {
    companion object {
        const val DEFAULT_MAX_ATTEMPT_LATENCY_MS = 3_000L
        private const val MAX_RETAINED_TERMINAL_IDS = 256
    }

    private var activeSessionId: String? = null
    private var observerReady = false
    private var activeAttempt: GateKActiveAttempt? = null
    private val terminalAttemptIds = LinkedHashSet<GateKAttemptId>()

    init {
        require(maxObservationLatencyMs > 0L) {
            "attempt latency threshold must be positive"
        }
    }

    @get:Synchronized
    val hasActiveAttempt: Boolean
        get() = activeAttempt != null

    @get:Synchronized
    val currentAttempt: GateKActiveAttempt?
        get() = activeAttempt

    @get:Synchronized
    val isObserverReady: Boolean
        get() = observerReady && activeSessionId != null

    @Synchronized
    fun onSessionShown(sessionId: String): Boolean {
        if (sessionId.isBlank()) return false
        activeSessionId = sessionId
        observerReady = false
        return true
    }

    @Synchronized
    fun markObserverReady(sessionId: String): Boolean {
        if (sessionId.isBlank() || activeSessionId != sessionId) return false
        observerReady = true
        return true
    }

    @Synchronized
    fun markObserverNotReady(sessionId: String): Boolean {
        if (activeSessionId != sessionId) return false
        observerReady = false
        return true
    }

    @Synchronized
    fun start(event: GateKAttemptStart): GateKAttemptStartResult {
        if (event.attemptId.value.isBlank()
            || event.sessionId.isBlank()
            || event.triggeredAtElapsedRealtimeMs < 0L
        ) {
            return GateKAttemptStartResult.RejectedInvalidEvent
        }
        if (event.attemptId in terminalAttemptIds) {
            return GateKAttemptStartResult.RejectedDuplicateAttemptId
        }
        if (activeSessionId == null) return GateKAttemptStartResult.RejectedNoActiveSession
        if (activeSessionId != event.sessionId) return GateKAttemptStartResult.RejectedWrongSession
        if (!observerReady) return GateKAttemptStartResult.RejectedObserverNotReady
        if (activeAttempt != null) return GateKAttemptStartResult.RejectedActiveAttempt

        val attempt = GateKActiveAttempt(
            attemptId = event.attemptId,
            sessionId = event.sessionId,
            triggeredAtElapsedRealtimeMs = event.triggeredAtElapsedRealtimeMs,
        )
        activeAttempt = attempt
        return GateKAttemptStartResult.Started(attempt)
    }

    /** Starts one explicit user/measurement attempt after the observer is ready. */
    @Synchronized
    fun begin(
        attemptId: GateKAttemptId,
        sessionId: String,
        monotonicStart: Long,
    ): GateKAttemptStartResult = start(
        GateKAttemptStart(
            attemptId = attemptId,
            sessionId = sessionId,
            triggeredAtElapsedRealtimeMs = monotonicStart,
        ),
    )

    @Synchronized
    fun detected(
        attemptId: GateKAttemptId,
        sessionId: String,
        detectedAtElapsedRealtimeMs: Long,
        sessionOutcome: GateKSessionOutcome,
        dedupeOutcome: GateKDedupeOutcome,
    ): GateKAttemptTerminalResult {
        val attempt = activeAttempt ?: return if (attemptId in terminalAttemptIds) {
            GateKAttemptTerminalResult.IgnoredAlreadyTerminal
        } else {
            GateKAttemptTerminalResult.IgnoredNoActiveAttempt
        }
        if (attempt.attemptId != attemptId) return GateKAttemptTerminalResult.IgnoredWrongAttempt
        if (attempt.sessionId != sessionId) return GateKAttemptTerminalResult.IgnoredWrongSession
        if (detectedAtElapsedRealtimeMs < attempt.triggeredAtElapsedRealtimeMs) {
            return GateKAttemptTerminalResult.RejectedInvalidTiming
        }
        val latencyMs = detectedAtElapsedRealtimeMs - attempt.triggeredAtElapsedRealtimeMs
        if (latencyMs > maxObservationLatencyMs) {
            return terminal(
                attempt = attempt,
                state = GateKAttemptState.TIMED_OUT,
                detectedAtElapsedRealtimeMs = detectedAtElapsedRealtimeMs,
                sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
                dedupeOutcome = GateKDedupeOutcome.NOT_EVALUATED,
                failureReason = GateKFailureReason.TIMEOUT,
            )
        }

        val verified = sessionOutcome == GateKSessionOutcome.ACCEPTED
            && dedupeOutcome == GateKDedupeOutcome.FIRST_SEEN
        return terminal(
            attempt = attempt,
            state = if (verified) GateKAttemptState.SUCCEEDED else GateKAttemptState.FAILED,
            detectedAtElapsedRealtimeMs = detectedAtElapsedRealtimeMs,
            sessionOutcome = sessionOutcome,
            dedupeOutcome = dedupeOutcome,
            failureReason = if (verified) {
                GateKFailureReason.NONE
            } else {
                GateKFailureReason.UNVERIFIED_OUTCOME
            },
        )
    }

    @Synchronized
    fun failed(
        attemptId: GateKAttemptId,
        sessionId: String,
        detectedAtElapsedRealtimeMs: Long,
        reason: GateKFailureReason,
    ): GateKAttemptTerminalResult {
        val attempt = activeAttempt ?: return if (attemptId in terminalAttemptIds) {
            GateKAttemptTerminalResult.IgnoredAlreadyTerminal
        } else {
            GateKAttemptTerminalResult.IgnoredNoActiveAttempt
        }
        if (attempt.attemptId != attemptId) return GateKAttemptTerminalResult.IgnoredWrongAttempt
        if (attempt.sessionId != sessionId) return GateKAttemptTerminalResult.IgnoredWrongSession
        if (detectedAtElapsedRealtimeMs < attempt.triggeredAtElapsedRealtimeMs) {
            return GateKAttemptTerminalResult.RejectedInvalidTiming
        }
        val latencyMs = detectedAtElapsedRealtimeMs - attempt.triggeredAtElapsedRealtimeMs
        if (latencyMs > maxObservationLatencyMs) {
            return terminal(
                attempt = attempt,
                state = GateKAttemptState.TIMED_OUT,
                detectedAtElapsedRealtimeMs = detectedAtElapsedRealtimeMs,
                sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
                dedupeOutcome = GateKDedupeOutcome.NOT_EVALUATED,
                failureReason = GateKFailureReason.TIMEOUT,
            )
        }
        return terminal(
            attempt = attempt,
            state = GateKAttemptState.FAILED,
            detectedAtElapsedRealtimeMs = detectedAtElapsedRealtimeMs,
            sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
            dedupeOutcome = GateKDedupeOutcome.NOT_EVALUATED,
            failureReason = if (reason == GateKFailureReason.NONE) {
                GateKFailureReason.INVALID_EVENT
            } else {
                reason
            },
        )
    }

    @Synchronized
    fun timeout(
        attemptId: GateKAttemptId,
        sessionId: String,
        nowElapsedRealtimeMs: Long,
    ): GateKAttemptTerminalResult {
        val attempt = activeAttempt ?: return if (attemptId in terminalAttemptIds) {
            GateKAttemptTerminalResult.IgnoredAlreadyTerminal
        } else {
            GateKAttemptTerminalResult.IgnoredNoActiveAttempt
        }
        if (attempt.attemptId != attemptId) return GateKAttemptTerminalResult.IgnoredWrongAttempt
        if (attempt.sessionId != sessionId) return GateKAttemptTerminalResult.IgnoredWrongSession
        if (nowElapsedRealtimeMs < attempt.triggeredAtElapsedRealtimeMs) {
            return GateKAttemptTerminalResult.RejectedInvalidTiming
        }
        val latencyMs = nowElapsedRealtimeMs - attempt.triggeredAtElapsedRealtimeMs
        // A latency of exactly three seconds is still inside the contract;
        // the handler retries one millisecond later before recording timeout.
        if (latencyMs <= maxObservationLatencyMs) {
            return GateKAttemptTerminalResult.WaitingForDeadline
        }
        return terminal(
            attempt = attempt,
            state = GateKAttemptState.TIMED_OUT,
            detectedAtElapsedRealtimeMs = nowElapsedRealtimeMs,
            sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
            dedupeOutcome = GateKDedupeOutcome.NOT_EVALUATED,
            failureReason = GateKFailureReason.TIMEOUT,
        )
    }

    @Synchronized
    fun onSessionHidden(
        sessionId: String,
        nowElapsedRealtimeMs: Long,
    ): GateKAttemptTerminalResult {
        val attempt = activeAttempt
        val result = when {
            activeSessionId != sessionId -> GateKAttemptTerminalResult.IgnoredWrongSession
            attempt == null -> GateKAttemptTerminalResult.IgnoredNoActiveAttempt
            nowElapsedRealtimeMs < attempt.triggeredAtElapsedRealtimeMs -> terminal(
                attempt = attempt,
                state = GateKAttemptState.FAILED,
                detectedAtElapsedRealtimeMs = attempt.triggeredAtElapsedRealtimeMs,
                sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
                dedupeOutcome = GateKDedupeOutcome.NOT_EVALUATED,
                failureReason = GateKFailureReason.INVALID_TIMING,
            )

            else -> terminal(
                attempt = attempt,
                state = GateKAttemptState.FAILED,
                detectedAtElapsedRealtimeMs = nowElapsedRealtimeMs,
                sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
                dedupeOutcome = GateKDedupeOutcome.NOT_EVALUATED,
                failureReason = GateKFailureReason.SESSION_ENDED,
            )
        }
        if (activeSessionId == sessionId) {
            activeSessionId = null
            observerReady = false
        }
        return result
    }

    private fun terminal(
        attempt: GateKActiveAttempt,
        state: GateKAttemptState,
        detectedAtElapsedRealtimeMs: Long,
        sessionOutcome: GateKSessionOutcome,
        dedupeOutcome: GateKDedupeOutcome,
        failureReason: GateKFailureReason,
    ): GateKAttemptTerminalResult.Recorded {
        val terminal = GateKAttemptTerminal(
            attemptId = attempt.attemptId,
            sessionId = attempt.sessionId,
            state = state,
            triggeredAtElapsedRealtimeMs = attempt.triggeredAtElapsedRealtimeMs,
            detectedAtElapsedRealtimeMs = detectedAtElapsedRealtimeMs,
            latencyMs = detectedAtElapsedRealtimeMs - attempt.triggeredAtElapsedRealtimeMs,
            sessionOutcome = sessionOutcome,
            dedupeOutcome = dedupeOutcome,
            failureReason = failureReason,
        )
        activeAttempt = null
        terminalAttemptIds += attempt.attemptId
        while (terminalAttemptIds.size > MAX_RETAINED_TERMINAL_IDS) {
            terminalAttemptIds.remove(terminalAttemptIds.first())
        }
        return GateKAttemptTerminalResult.Recorded(terminal)
    }

}
