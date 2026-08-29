package com.vibesync.gatek

/**
 * Bounded retry policy for a MediaStore row whose notification arrived before
 * its readable metadata or bytes were complete. The caller still owns the
 * exact-row requery and observation; this class only makes the retry budget
 * and cancellation behavior deterministic and testable.
 */
enum class GateKCandidateReadinessFailure {
    CONTENT_UNAVAILABLE,
    METADATA_REJECTED,
    GRANT_UNAVAILABLE,
    QUERY_FAILED,
    OBSERVER_ERROR,
}

/**
 * Bounded provider failures used by the Android seam.  These names are
 * intentionally narrower than exception text so the evidence vocabulary
 * cannot grow with provider implementation details.
 */
enum class GateKCandidateReadinessProviderFailure {
    ROW_NOT_FOUND,
    SECURITY_EXCEPTION,
    NULL_CURSOR,
    QUERY_EXCEPTION,
    CONTENT_IO_EXCEPTION,
    CONTENT_STREAM_UNAVAILABLE,
    EXPECTED_VERSION_MISSING,
    EXPECTED_VERSION_CHANGED,
    IDENTITY_MISMATCH,
    METADATA_MISMATCH,
}

sealed interface GateKCandidateReadinessProbeResult {
    data class Observed(val result: GateKObservationResult) : GateKCandidateReadinessProbeResult

    data class Retryable(val failure: GateKCandidateReadinessFailure) :
        GateKCandidateReadinessProbeResult

    data class Failed(val failure: GateKCandidateReadinessFailure) :
        GateKCandidateReadinessProbeResult

    /** The attempt deadline was reached before a new read/hash could begin. */
    data object DeadlineReached : GateKCandidateReadinessProbeResult

    data object SessionEnded : GateKCandidateReadinessProbeResult
}

sealed interface GateKCandidateReadinessResult {
    data class Observed(val result: GateKObservationResult) : GateKCandidateReadinessResult

    data class Failed(val failure: GateKCandidateReadinessFailure) : GateKCandidateReadinessResult

    data object DeadlineReached : GateKCandidateReadinessResult

    data object SessionEnded : GateKCandidateReadinessResult
}

/**
 * Keeps the retry boundary separate from the Android provider seam. Only the
 * two rejection reasons that can be caused by a row becoming ready later are
 * retryable; session, source, and identity failures remain terminal.
 */
object GateKCandidateReadinessPolicy {
    fun classify(result: GateKObservationResult): GateKCandidateReadinessProbeResult =
        when (result) {
            is GateKObservationResult.Accepted,
            is GateKObservationResult.DuplicateSuppressed ->
                GateKCandidateReadinessProbeResult.Observed(result)

            is GateKObservationResult.Rejected -> when (result.reason) {
                GateKObservationRejectReason.INVALID_DIMENSIONS,
                GateKObservationRejectReason.EMPTY_CONTENT ->
                    GateKCandidateReadinessProbeResult.Retryable(
                        GateKCandidateReadinessFailure.METADATA_REJECTED,
                    )

                else -> GateKCandidateReadinessProbeResult.Failed(
                    GateKCandidateReadinessFailure.METADATA_REJECTED,
                )
            }

            is GateKObservationResult.Ignored ->
                GateKCandidateReadinessProbeResult.Failed(
                    GateKCandidateReadinessFailure.METADATA_REJECTED,
                )
        }

    /** Maps provider seams without retrying failures that cannot become ready. */
    fun classifyProviderFailure(
        failure: GateKCandidateReadinessProviderFailure,
    ): GateKCandidateReadinessProbeResult = when (failure) {
        GateKCandidateReadinessProviderFailure.ROW_NOT_FOUND ->
            GateKCandidateReadinessProbeResult.Retryable(
                GateKCandidateReadinessFailure.CONTENT_UNAVAILABLE,
            )

        GateKCandidateReadinessProviderFailure.SECURITY_EXCEPTION ->
            GateKCandidateReadinessProbeResult.Failed(
                GateKCandidateReadinessFailure.GRANT_UNAVAILABLE,
            )

        GateKCandidateReadinessProviderFailure.NULL_CURSOR,
        GateKCandidateReadinessProviderFailure.QUERY_EXCEPTION ->
            GateKCandidateReadinessProbeResult.Failed(
                GateKCandidateReadinessFailure.QUERY_FAILED,
            )

        GateKCandidateReadinessProviderFailure.CONTENT_IO_EXCEPTION,
        GateKCandidateReadinessProviderFailure.CONTENT_STREAM_UNAVAILABLE ->
            GateKCandidateReadinessProbeResult.Retryable(
                GateKCandidateReadinessFailure.CONTENT_UNAVAILABLE,
            )

        GateKCandidateReadinessProviderFailure.EXPECTED_VERSION_MISSING,
        GateKCandidateReadinessProviderFailure.EXPECTED_VERSION_CHANGED ->
            GateKCandidateReadinessProbeResult.Failed(
                GateKCandidateReadinessFailure.OBSERVER_ERROR,
            )

        GateKCandidateReadinessProviderFailure.IDENTITY_MISMATCH,
        GateKCandidateReadinessProviderFailure.METADATA_MISMATCH ->
            GateKCandidateReadinessProbeResult.Failed(
                GateKCandidateReadinessFailure.METADATA_REJECTED,
            )
    }

    /**
     * Validates a retry against the version captured by the session baseline.
     * Both a missing version and a changed version invalidate the observation;
     * a query-local before/after equality is not sufficient.
     */
    fun classifyExpectedMediaStoreVersion(
        expectedVersion: String?,
        observedVersion: String?,
    ): GateKCandidateReadinessProbeResult? {
        val failure = when {
            expectedVersion.isNullOrBlank() || observedVersion.isNullOrBlank() ->
                GateKCandidateReadinessProviderFailure.EXPECTED_VERSION_MISSING

            expectedVersion != observedVersion ->
                GateKCandidateReadinessProviderFailure.EXPECTED_VERSION_CHANGED

            else -> null
        }
        return failure?.let { classifyProviderFailure(it) }
    }

    /** True after the deadline, preventing a late open/hash. */
    fun isDeadlineReached(
        triggeredAtElapsedRealtimeMs: Long,
        nowElapsedRealtimeMs: Long,
        deadlineMs: Long = GateKAttemptCoordinator.DEFAULT_MAX_ATTEMPT_LATENCY_MS,
    ): Boolean {
        require(triggeredAtElapsedRealtimeMs >= 0L) {
            "attempt start must not be negative"
        }
        require(nowElapsedRealtimeMs >= 0L) {
            "current elapsed time must not be negative"
        }
        require(deadlineMs > 0L) { "attempt deadline must be positive" }
        return nowElapsedRealtimeMs >= triggeredAtElapsedRealtimeMs
            && nowElapsedRealtimeMs - triggeredAtElapsedRealtimeMs > deadlineMs
    }

    fun GateKCandidateReadinessFailure.toGateKFailureReason(): GateKFailureReason = when (this) {
        GateKCandidateReadinessFailure.CONTENT_UNAVAILABLE ->
            GateKFailureReason.CONTENT_UNAVAILABLE

        GateKCandidateReadinessFailure.METADATA_REJECTED ->
            GateKFailureReason.METADATA_REJECTED

        GateKCandidateReadinessFailure.GRANT_UNAVAILABLE ->
            GateKFailureReason.GRANT_UNAVAILABLE

        GateKCandidateReadinessFailure.QUERY_FAILED ->
            GateKFailureReason.QUERY_FAILED

        GateKCandidateReadinessFailure.OBSERVER_ERROR ->
            GateKFailureReason.OBSERVER_ERROR
    }
}

/**
 * Runs a small, worker-thread-only retry loop. It never turns a permanently
 * invalid candidate into a success: retryable observations become a bounded
 * failure once the budget is exhausted.
 */
class GateKCandidateReadinessRetry(
    private val maxRetries: Int = DEFAULT_MAX_RETRIES,
    private val retryDelayMs: Long = DEFAULT_RETRY_DELAY_MS,
    private val sleep: (Long) -> Unit = { delay -> Thread.sleep(delay) },
) {
    companion object {
        const val DEFAULT_MAX_RETRIES = 8
        const val DEFAULT_RETRY_DELAY_MS = 100L
    }

    init {
        require(maxRetries >= 0) { "candidate readiness retry budget must not be negative" }
        require(retryDelayMs >= 0L) { "candidate readiness retry delay must not be negative" }
    }

    fun resolve(probe: () -> GateKCandidateReadinessProbeResult): GateKCandidateReadinessResult {
        var retries = 0
        while (true) {
            when (val result = probe()) {
                is GateKCandidateReadinessProbeResult.Observed ->
                    return GateKCandidateReadinessResult.Observed(result.result)

                is GateKCandidateReadinessProbeResult.Failed ->
                    return GateKCandidateReadinessResult.Failed(result.failure)

                GateKCandidateReadinessProbeResult.SessionEnded ->
                    return GateKCandidateReadinessResult.SessionEnded

                GateKCandidateReadinessProbeResult.DeadlineReached ->
                    return GateKCandidateReadinessResult.DeadlineReached

                is GateKCandidateReadinessProbeResult.Retryable -> {
                    if (retries >= maxRetries) {
                        return GateKCandidateReadinessResult.Failed(result.failure)
                    }
                    retries += 1
                    if (retryDelayMs > 0L) {
                        try {
                            sleep(retryDelayMs)
                        } catch (_: InterruptedException) {
                            Thread.currentThread().interrupt()
                            return GateKCandidateReadinessResult.SessionEnded
                        }
                    }
                }
            }
        }
    }
}
