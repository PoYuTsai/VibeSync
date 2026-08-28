package com.vibesync.gatek

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MediaStoreSessionBaselineTest {
    @Test
    fun `initial baseline keeps only the newest generation high water mark`() {
        val baseline = GateKMediaStoreSessionBaseline()

        val result = baseline.beginSession(
            floorEpochMs = 100_500L,
            existingRecords = listOf(record(id = "latest", generation = 7L)),
        )

        assertEquals(
            GateKMediaStoreBaselineStartResult.Started(highWaterGeneration = 7L),
            result,
        )
        assertEquals(7L, baseline.currentHighWaterGeneration)
        assertTrue(baseline.isActive)
    }

    @Test
    fun `old generations do not return and a newer generation returns once`() {
        val baseline = GateKMediaStoreSessionBaseline()
        baseline.beginSession(
            floorEpochMs = 100_500L,
            existingRecords = listOf(record(id = "old", generation = 7L)),
        )
        val newScreenshot = record(
            id = "new",
            generation = 8L,
            dateAddedSec = 101L,
        )

        val first = baseline.queryNewRecords(
            notificationUri = null,
            queriedRecords = listOf(
                record(id = "older", generation = 6L),
                record(id = "old", generation = 7L),
                newScreenshot,
            ),
        )

        assertEquals(
            listOf(
                newScreenshot.copy(
                    metadata = newScreenshot.metadata.copy(observedAtEpochMs = 100_501L),
                ),
            ),
            first.candidates,
        )
        assertEquals(null, first.failure)
        assertEquals(8L, baseline.currentHighWaterGeneration)
        assertEquals(
            emptyList<MediaStoreCandidateRecord>(),
            baseline.queryNewRecords(
                notificationUri = "content://media/external/images/media",
                queriedRecords = listOf(newScreenshot),
            ).candidates,
        )
    }

    @Test
    fun `same row resent with the same generation is not a second candidate`() {
        val baseline = GateKMediaStoreSessionBaseline()
        baseline.beginSession(
            floorEpochMs = 10_000L,
            existingRecords = listOf(record(id = "old", generation = 2L)),
        )
        val newRow = record(id = "new", generation = 3L, dateAddedSec = 11L)

        assertEquals(1, baseline.onContentObserverNotification(null, listOf(newRow)).size)
        assertEquals(0, baseline.onContentObserverNotification(null, listOf(newRow)).size)
    }

    @Test
    fun `initial overflow, delta overflow, missing generation and invalid row fail closed`() {
        val initialOverflow = GateKMediaStoreSessionBaseline().beginSession(
            floorEpochMs = 1_000L,
            existingRecords = listOf(
                record(id = "a", generation = 1L),
                record(id = "b", generation = 2L),
            ),
        )
        assertEquals(
            GateKMediaStoreBaselineStartResult.Rejected(
                GateKMediaStoreBaselineFailure.INITIAL_QUERY_OVERFLOW,
            ),
            initialOverflow,
        )

        val baseline = GateKMediaStoreSessionBaseline()
        baseline.beginSession(
            floorEpochMs = 1_000L,
            existingRecords = listOf(record(id = "old", generation = 1L)),
        )
        val overflow = baseline.queryNewRecords(
            notificationUri = null,
            queriedRecords = (2L..130L).map { generation ->
                record(id = "id-$generation", generation = generation)
            },
        )
        assertEquals(GateKMediaStoreBaselineFailure.DELTA_QUERY_OVERFLOW, overflow.failure)
        assertTrue(overflow.candidates.isEmpty())
        assertEquals(1L, baseline.currentHighWaterGeneration)

        val blocked = baseline.queryNewRecords(
            notificationUri = null,
            queriedRecords = listOf(record(id = "new", generation = 2L)),
        )
        assertEquals(GateKMediaStoreBaselineFailure.DELTA_QUERY_OVERFLOW, blocked.failure)

        val missingGenerationBaseline = GateKMediaStoreSessionBaseline()
        missingGenerationBaseline.beginSession(
            floorEpochMs = 1_000L,
            existingRecords = listOf(record(id = "old", generation = 1L)),
        )
        val missing = missingGenerationBaseline.queryNewRecords(
            notificationUri = null,
            queriedRecords = listOf(record(id = "missing", generation = null)),
        )
        assertEquals(GateKMediaStoreBaselineFailure.MISSING_GENERATION, missing.failure)
        assertTrue(missing.candidates.isEmpty())

        val invalidBaseline = GateKMediaStoreSessionBaseline()
        invalidBaseline.beginSession(
            floorEpochMs = 1_000L,
            existingRecords = listOf(record(id = "old", generation = 1L)),
        )
        val invalid = invalidBaseline.queryNewRecords(
            notificationUri = null,
            queriedRecords = listOf(record(id = "", generation = 2L)),
        )
        assertEquals(GateKMediaStoreBaselineFailure.INVALID_RECORD, invalid.failure)
        assertFalse(invalidBaseline.currentHighWaterGeneration == 2L)
    }

    @Test
    fun `query contract is bounded and generation ordered`() {
        val initial = GateKMediaStoreQueryContract.initialBaseline()
        assertEquals(GateKMediaStoreQueryPhase.INITIAL_BASELINE, initial.phase)
        assertEquals(1, initial.limit)
        assertEquals(1, initial.maxRows)
        assertEquals("is_pending = ?", initial.selection)
        assertEquals(listOf("0"), initial.selectionArgs)
        assertEquals("generation_added", initial.sortColumn)
        assertFalse(initial.sortAscending)

        val delta = GateKMediaStoreQueryContract.observerDelta(12L)
        assertEquals(GateKMediaStoreQueryPhase.OBSERVER_DELTA, delta.phase)
        assertEquals("is_pending = ? AND generation_added > ?", delta.selection)
        assertEquals(listOf("0", "12"), delta.selectionArgs)
        assertEquals("generation_added", delta.sortColumn)
        assertTrue(delta.sortAscending)
        assertEquals(129, delta.limit)
        assertEquals(128, delta.maxRows)
    }

    @Test
    fun `out of order generation batch fails closed without advancing high water`() {
        val baseline = GateKMediaStoreSessionBaseline()
        baseline.beginSession(
            floorEpochMs = 1_000L,
            existingRecords = listOf(record(id = "old", generation = 1L)),
        )

        val result = baseline.queryNewRecords(
            notificationUri = null,
            queriedRecords = listOf(
                record(id = "new-3", generation = 3L),
                record(id = "new-2", generation = 2L),
            ),
        )

        assertEquals(GateKMediaStoreBaselineFailure.OUT_OF_ORDER_GENERATION, result.failure)
        assertTrue(result.candidates.isEmpty())
        assertEquals(1L, baseline.currentHighWaterGeneration)
    }

    private fun record(
        id: String,
        generation: Long?,
        dateAddedSec: Long = 100L,
    ): MediaStoreCandidateRecord = MediaStoreCandidateRecord(
        mediaId = id,
        generation = generation,
        dateAddedEpochSec = dateAddedSec,
        metadata = MediaStoreImageMetadata(
            uri = "content://media/external/images/media/${id.ifBlank { "invalid" }}",
            relativePath = "Pictures/Screenshots/",
            mimeType = "image/png",
            width = 1080,
            height = 1920,
        ),
    )
}
