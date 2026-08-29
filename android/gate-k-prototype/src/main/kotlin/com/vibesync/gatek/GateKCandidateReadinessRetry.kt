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
}

sealed interface GateKCandidateReadinessProbeResult {
    data class Observed(val result: GateKObservationResult) : GateKCandidateReadinessProbeResult

    data class Retryable(val failure: GateKCandidateReadinessFailure) :
        GateKCandidateReadinessProbeResult

    data class Failed(val failure: GateKCandidateReadinessFailure) :
        GateKCandidateReadinessProbeResult

    data object SessionEnded : GateKCandidateReadinessProbeResult
}

sealed interface GateKCandidateReadinessResult {
    data class Observed(val result: GateKObservationResult) : GateKCandidateReadinessResult

    data class Failed(val failure: GateKCandidateReadinessFailure) : GateKCandidateReadinessResult

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
