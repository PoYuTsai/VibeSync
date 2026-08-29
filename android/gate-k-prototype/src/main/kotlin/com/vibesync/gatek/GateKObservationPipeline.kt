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
 * First phase of an observation. The accepted branch only snapshots the
 * immutable session/filter inputs; hashing is deliberately deferred until
 * the active-read lease can provide cancellation checks.
 */
internal sealed interface GateKObservationPreparation {
    data class Accepted(
        val window: ImeSessionWindow,
        val candidate: ScreenshotCandidate,
    ) : GateKObservationPreparation

    data class Terminal(val result: GateKObservationResult) : GateKObservationPreparation
}

/** A hash prepared without mutating the session-scoped dedupe state. */
internal sealed interface GateKPreparedObservation {
    data class Ready(
        val observation: GateKObservationPreparation.Accepted,
        val identity: CandidateIdentity,
    ) : GateKPreparedObservation

    data class Terminal(val result: GateKObservationResult) : GateKPreparedObservation
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

    /**
     * Performs only the short, side-effect-free filter phase. Callers should
     * hold their lifecycle/pipeline lock while invoking this method.
     */
    internal fun prepareObservation(candidate: ScreenshotCandidate): GateKObservationPreparation {
        val currentWindow = sessionFloor.current
        return when (val filtered = ScreenshotCandidateFilter.observe(currentWindow, candidate)) {
            is ScreenshotObservationDecision.Accepted -> {
                val window = currentWindow
                    ?: return GateKObservationPreparation.Terminal(
                        GateKObservationResult.Ignored(IgnoredCandidateReason.NO_ACTIVE_SESSION),
                    )
                GateKObservationPreparation.Accepted(window, filtered.candidate)
            }

            is ScreenshotObservationDecision.Ignored ->
                GateKObservationPreparation.Terminal(
                    GateKObservationResult.Ignored(filtered.reason),
                )

            is ScreenshotObservationDecision.Rejected ->
                GateKObservationPreparation.Terminal(
                    GateKObservationResult.Rejected(filtered.reason.toPipelineReason()),
                )
        }
    }

    /** Hashes only; no dedupe/session state is changed in this phase. */
    internal fun prepareAcceptedObservation(
        preparation: GateKObservationPreparation.Accepted,
        shouldContinue: () -> Boolean,
    ): CandidateIdentity? =
        dedupe.prepareIdentity(preparation.candidate.content, shouldContinue)

    /**
     * Commits a prepared observation. The caller must invoke this from the
     * lease's linearizable commit gate; this method itself only performs the
     * short mutable dedupe update after revalidating the exact session window.
     */
    internal fun commitPreparedObservation(
        prepared: GateKPreparedObservation,
    ): GateKObservationResult {
        when (prepared) {
            is GateKPreparedObservation.Terminal -> return prepared.result
            is GateKPreparedObservation.Ready -> Unit
        }
        val ready = prepared as GateKPreparedObservation.Ready
        val currentWindow = sessionFloor.current
            ?: return GateKObservationResult.Ignored(IgnoredCandidateReason.NO_ACTIVE_SESSION)
        if (currentWindow != ready.observation.window) {
            return GateKObservationResult.Ignored(IgnoredCandidateReason.WRONG_SESSION)
        }
        return when (
            val filtered = ScreenshotCandidateFilter.observe(
                currentWindow,
                ready.observation.candidate,
            )
        ) {
            is ScreenshotObservationDecision.Accepted ->
                dedupe.observePrepared(
                    window = currentWindow,
                    candidate = filtered.candidate,
                    identity = ready.identity,
                ).toObservationResult()

            is ScreenshotObservationDecision.Ignored ->
                GateKObservationResult.Ignored(filtered.reason)

            is ScreenshotObservationDecision.Rejected ->
                GateKObservationResult.Rejected(filtered.reason.toPipelineReason())
        }
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

    private fun CandidateIdentityDecision.toObservationResult(): GateKObservationResult {
        return when (this) {
            is CandidateIdentityDecision.FirstSeen ->
                GateKObservationResult.Accepted(identity)

            is CandidateIdentityDecision.Duplicate ->
                GateKObservationResult.DuplicateSuppressed(identity)

            CandidateIdentityDecision.RejectedEmptyContent ->
                GateKObservationResult.Rejected(GateKObservationRejectReason.EMPTY_CONTENT)

            CandidateIdentityDecision.RejectedStaleSession ->
                GateKObservationResult.Rejected(GateKObservationRejectReason.STALE_SESSION)

            CandidateIdentityDecision.RejectedWrongSession ->
                GateKObservationResult.Rejected(GateKObservationRejectReason.WRONG_SESSION)
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
