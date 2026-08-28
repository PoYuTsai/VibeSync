package com.vibesync.gatek

sealed interface GateKObservationResult {
    data class Accepted(val identity: CandidateIdentity) : GateKObservationResult

    data class DuplicateSuppressed(val identity: CandidateIdentity) : GateKObservationResult

    data class Ignored(val reason: IgnoredCandidateReason) : GateKObservationResult

    data class Rejected(val reason: GateKObservationRejectReason) : GateKObservationResult
}

enum class GateKObservationRejectReason {
    UNSUPPORTED_SOURCE,
    INVALID_DIMENSIONS,
    EMPTY_CONTENT,
    WRONG_SESSION,
    STALE_SESSION,
}

/**
 * The single public observation boundary used by the prototype IME. It
 * exposes identities and decisions, never image bytes or chat content.
 */
class GateKObservationPipeline(
    private val sessionFloor: ImeSessionFloor = ImeSessionFloor(),
    private val dedupe: ScreenshotCandidateDedupe = ScreenshotCandidateDedupe(),
) {
    fun onImeShown(event: ImeSessionStart): ImeSessionStartResult = sessionFloor.start(event)

    fun onImeHidden(event: ImeSessionEnd): ImeSessionEndResult =
        sessionFloor.end(event).also { result ->
            if (result is ImeSessionEndResult.Ended) dedupe.clear()
        }

    fun observe(candidate: ScreenshotCandidate): GateKObservationResult {
        val currentWindow = sessionFloor.current
        return when (val filtered = ScreenshotCandidateFilter.observe(currentWindow, candidate)) {
            is ScreenshotObservationDecision.Accepted -> {
                val window = currentWindow ?: return GateKObservationResult.Ignored(
                    IgnoredCandidateReason.NO_ACTIVE_SESSION,
                )
                when (val identity = dedupe.observe(window, filtered.candidate)) {
                    is CandidateIdentityDecision.FirstSeen ->
                        GateKObservationResult.Accepted(identity.identity)

                    is CandidateIdentityDecision.Duplicate ->
                        GateKObservationResult.DuplicateSuppressed(identity.identity)

                    CandidateIdentityDecision.RejectedEmptyContent ->
                        GateKObservationResult.Rejected(GateKObservationRejectReason.EMPTY_CONTENT)

                    CandidateIdentityDecision.RejectedStaleSession ->
                        GateKObservationResult.Rejected(GateKObservationRejectReason.STALE_SESSION)

                    CandidateIdentityDecision.RejectedWrongSession ->
                        GateKObservationResult.Rejected(GateKObservationRejectReason.WRONG_SESSION)
                }
            }

            is ScreenshotObservationDecision.Ignored ->
                GateKObservationResult.Ignored(filtered.reason)

            is ScreenshotObservationDecision.Rejected ->
                GateKObservationResult.Rejected(filtered.reason.toPipelineReason())
        }
    }

    private fun RejectedCandidateReason.toPipelineReason(): GateKObservationRejectReason = when (this) {
        RejectedCandidateReason.UNSUPPORTED_SOURCE ->
            GateKObservationRejectReason.UNSUPPORTED_SOURCE

        RejectedCandidateReason.INVALID_DIMENSIONS ->
            GateKObservationRejectReason.INVALID_DIMENSIONS

        RejectedCandidateReason.EMPTY_CONTENT ->
            GateKObservationRejectReason.EMPTY_CONTENT
    }
}
