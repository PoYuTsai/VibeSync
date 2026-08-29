package com.vibesync.gatek

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GateKCandidateReadinessRetryTest {
    @Test
    fun `only transient metadata rejects are retryable`() {
        val ready = GateKObservationResult.Accepted(CandidateIdentity("ready"))
        val duplicate = GateKObservationResult.DuplicateSuppressed(CandidateIdentity("duplicate"))

        assertTrue(GateKCandidateReadinessPolicy.classify(ready)
            is GateKCandidateReadinessProbeResult.Observed)
        assertTrue(GateKCandidateReadinessPolicy.classify(duplicate)
            is GateKCandidateReadinessProbeResult.Observed)

        assertEquals(
            GateKCandidateReadinessProbeResult.Retryable(
                GateKCandidateReadinessFailure.METADATA_REJECTED,
            ),
            GateKCandidateReadinessPolicy.classify(
                GateKObservationResult.Rejected(GateKObservationRejectReason.INVALID_DIMENSIONS),
            ),
        )
        assertEquals(
            GateKCandidateReadinessProbeResult.Retryable(
                GateKCandidateReadinessFailure.METADATA_REJECTED,
            ),
            GateKCandidateReadinessPolicy.classify(
                GateKObservationResult.Rejected(GateKObservationRejectReason.EMPTY_CONTENT),
            ),
        )
        assertEquals(
            GateKCandidateReadinessProbeResult.Failed(
                GateKCandidateReadinessFailure.METADATA_REJECTED,
            ),
            GateKCandidateReadinessPolicy.classify(
                GateKObservationResult.Rejected(GateKObservationRejectReason.UNSUPPORTED_SOURCE),
            ),
        )
        assertEquals(
            GateKCandidateReadinessProbeResult.Failed(
                GateKCandidateReadinessFailure.METADATA_REJECTED,
            ),
            GateKCandidateReadinessPolicy.classify(
                GateKObservationResult.Rejected(GateKObservationRejectReason.WRONG_SESSION),
            ),
        )
        assertEquals(
            GateKCandidateReadinessProbeResult.Failed(
                GateKCandidateReadinessFailure.METADATA_REJECTED,
            ),
            GateKCandidateReadinessPolicy.classify(
                GateKObservationResult.Rejected(GateKObservationRejectReason.STALE_SESSION),
            ),
        )
        assertTrue(
            GateKCandidateReadinessPolicy.classify(
                GateKObservationResult.Ignored(IgnoredCandidateReason.NO_ACTIVE_SESSION),
            ) is GateKCandidateReadinessProbeResult.Failed,
        )
    }

    @Test
    fun `transient metadata rejection is rechecked before terminalizing the attempt`() {
        var probes = 0
        val delays = mutableListOf<Long>()
        val result = GateKCandidateReadinessRetry(
            maxRetries = 3,
            retryDelayMs = 25L,
            sleep = { delay -> delays += delay },
        ).resolve {
            probes += 1
            if (probes == 1) {
                GateKCandidateReadinessProbeResult.Retryable(
                    GateKCandidateReadinessFailure.METADATA_REJECTED,
                )
            } else {
                GateKCandidateReadinessProbeResult.Observed(
                    GateKObservationResult.Accepted(CandidateIdentity("ready")),
                )
            }
        }

        assertEquals(
            GateKCandidateReadinessResult.Observed(
                GateKObservationResult.Accepted(CandidateIdentity("ready")),
            ),
            result,
        )
        assertEquals(2, probes)
        assertEquals(listOf(25L), delays)
    }

    @Test
    fun `permanently invalid metadata fails after the bounded retry budget`() {
        var probes = 0
        val result = GateKCandidateReadinessRetry(
            maxRetries = 2,
            retryDelayMs = 0L,
        ).resolve {
            probes += 1
            GateKCandidateReadinessProbeResult.Retryable(
                GateKCandidateReadinessFailure.METADATA_REJECTED,
            )
        }

        assertEquals(
            GateKCandidateReadinessResult.Failed(
                GateKCandidateReadinessFailure.METADATA_REJECTED,
            ),
            result,
        )
        assertEquals(3, probes)
    }

    @Test
    fun `session ending aborts the retry without manufacturing an outcome`() {
        var probes = 0
        val result = GateKCandidateReadinessRetry(
            maxRetries = 3,
            retryDelayMs = 0L,
        ).resolve {
            probes += 1
            if (probes == 1) {
                GateKCandidateReadinessProbeResult.Retryable(
                    GateKCandidateReadinessFailure.CONTENT_UNAVAILABLE,
                )
            } else {
                GateKCandidateReadinessProbeResult.SessionEnded
            }
        }

        assertTrue(result is GateKCandidateReadinessResult.SessionEnded)
        assertEquals(2, probes)
    }
}
