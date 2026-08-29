package com.vibesync.gatek

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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
    fun `provider failures map to bounded terminal or retryable outcomes`() {
        assertEquals(
            GateKCandidateReadinessProbeResult.Retryable(
                GateKCandidateReadinessFailure.CONTENT_UNAVAILABLE,
            ),
            GateKCandidateReadinessPolicy.classifyProviderFailure(
                GateKCandidateReadinessProviderFailure.ROW_NOT_FOUND,
            ),
        )
        assertEquals(
            GateKCandidateReadinessProbeResult.Failed(
                GateKCandidateReadinessFailure.GRANT_UNAVAILABLE,
            ),
            GateKCandidateReadinessPolicy.classifyProviderFailure(
                GateKCandidateReadinessProviderFailure.SECURITY_EXCEPTION,
            ),
        )
        listOf(
            GateKCandidateReadinessProviderFailure.NULL_CURSOR,
            GateKCandidateReadinessProviderFailure.QUERY_EXCEPTION,
        ).forEach { failure ->
            assertEquals(
                GateKCandidateReadinessProbeResult.Failed(
                    GateKCandidateReadinessFailure.QUERY_FAILED,
                ),
                GateKCandidateReadinessPolicy.classifyProviderFailure(failure),
            )
        }
        listOf(
            GateKCandidateReadinessProviderFailure.EXPECTED_VERSION_MISSING,
            GateKCandidateReadinessProviderFailure.EXPECTED_VERSION_CHANGED,
        ).forEach { failure ->
            assertEquals(
                GateKCandidateReadinessProbeResult.Failed(
                    GateKCandidateReadinessFailure.OBSERVER_ERROR,
                ),
                GateKCandidateReadinessPolicy.classifyProviderFailure(failure),
            )
        }
        listOf(
            GateKCandidateReadinessProviderFailure.IDENTITY_MISMATCH,
            GateKCandidateReadinessProviderFailure.METADATA_MISMATCH,
        ).forEach { failure ->
            assertEquals(
                GateKCandidateReadinessProbeResult.Failed(
                    GateKCandidateReadinessFailure.METADATA_REJECTED,
                ),
                GateKCandidateReadinessPolicy.classifyProviderFailure(failure),
            )
        }
    }

    @Test
    fun `retry rejects a version changed before the exact query`() {
        assertEquals(
            GateKCandidateReadinessProbeResult.Failed(
                GateKCandidateReadinessFailure.OBSERVER_ERROR,
            ),
            GateKCandidateReadinessPolicy.classifyExpectedMediaStoreVersion(
                expectedVersion = "baseline-v1",
                observedVersion = "baseline-v2",
            ),
        )
    }

    @Test
    fun `retry rejects a version changed during query before pipeline`() {
        assertEquals(
            GateKCandidateReadinessProbeResult.Failed(
                GateKCandidateReadinessFailure.OBSERVER_ERROR,
            ),
            GateKCandidateReadinessPolicy.classifyExpectedMediaStoreVersion(
                expectedVersion = "baseline-v1",
                observedVersion = "baseline-v3",
            ),
        )
        assertNull(
            GateKCandidateReadinessPolicy.classifyExpectedMediaStoreVersion(
                expectedVersion = "baseline-v1",
                observedVersion = "baseline-v1",
            ),
        )
    }

    @Test
    fun `query open and hash gates stop at the three second deadline`() {
        val start = 10_000L
        assertFalse(
            GateKCandidateReadinessPolicy.isDeadlineReached(
                triggeredAtElapsedRealtimeMs = start,
                nowElapsedRealtimeMs = start + 2_999L,
            ),
        )
        assertFalse(
            GateKCandidateReadinessPolicy.isDeadlineReached(
                triggeredAtElapsedRealtimeMs = start,
                nowElapsedRealtimeMs = start + 3_000L,
            ),
        )
        assertTrue(
            GateKCandidateReadinessPolicy.isDeadlineReached(
                triggeredAtElapsedRealtimeMs = start,
                nowElapsedRealtimeMs = start + 3_001L,
            ),
        )
        assertEquals(
            GateKCandidateReadinessResult.DeadlineReached,
            GateKCandidateReadinessRetry(
                maxRetries = 8,
                retryDelayMs = 0L,
            ).resolve { GateKCandidateReadinessProbeResult.DeadlineReached },
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
