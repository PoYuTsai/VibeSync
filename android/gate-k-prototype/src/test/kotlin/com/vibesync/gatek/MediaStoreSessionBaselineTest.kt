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
            versionSnapshot = version(),
        )

        assertEquals(
            GateKMediaStoreBaselineStartResult.Started(
                highWaterGeneration = 7L,
                mediaStoreVersion = "media-store-v1",
            ),
            result,
        )
        assertEquals(7L, baseline.currentHighWaterGeneration)
        assertEquals("media-store-v1", baseline.currentMediaStoreVersion)
        assertTrue(baseline.isActive)
    }

    @Test
    fun `pending rows skipped by the query still advance the initial high water mark`() {
        val baseline = GateKMediaStoreSessionBaseline()

        val result = baseline.beginSession(
            floorEpochMs = 100_500L,
            existingRecords = emptyList(),
            initialHighWaterGeneration = 7L,
            versionSnapshot = version(),
        )

        assertEquals(
            GateKMediaStoreBaselineStartResult.Started(
                highWaterGeneration = 7L,
                mediaStoreVersion = "media-store-v1",
            ),
            result,
        )
        assertEquals(7L, baseline.currentHighWaterGeneration)
    }

    @Test
    fun `old generations do not return and a newer generation returns once`() {
        val baseline = GateKMediaStoreSessionBaseline()
        baseline.beginSession(
            floorEpochMs = 100_500L,
            existingRecords = listOf(record(id = "old", generation = 7L)),
            versionSnapshot = version(),
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
            versionSnapshot = version(),
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
                versionSnapshot = version(),
            ).candidates,
        )
    }

    @Test
    fun `same row resent with the same generation is not a second candidate`() {
        val baseline = GateKMediaStoreSessionBaseline()
        baseline.beginSession(
            floorEpochMs = 10_000L,
            existingRecords = listOf(record(id = "old", generation = 2L)),
            versionSnapshot = version(),
        )
        val newRow = record(id = "new", generation = 3L, dateAddedSec = 11L)

        assertEquals(
            1,
            baseline.queryNewRecords(null, listOf(newRow), version()).candidates.size,
        )
        assertEquals(
            0,
            baseline.queryNewRecords(null, listOf(newRow), version()).candidates.size,
        )
    }

    @Test
    fun `pending delta high water prevents a later publish from becoming a candidate`() {
        val baseline = GateKMediaStoreSessionBaseline()
        baseline.beginSession(
            floorEpochMs = 10_000L,
            existingRecords = emptyList(),
            versionSnapshot = version(),
        )

        val pendingDelta = baseline.queryNewRecords(
            notificationUri = null,
            queriedRecords = emptyList(),
            queriedHighWaterGeneration = 4L,
            versionSnapshot = version(),
        )
        assertEquals(emptyList<MediaStoreCandidateRecord>(), pendingDelta.candidates)
        assertEquals(4L, baseline.currentHighWaterGeneration)

        val published = baseline.queryNewRecords(
            notificationUri = null,
            queriedRecords = listOf(record(id = "published", generation = 4L, dateAddedSec = 11L)),
            versionSnapshot = version(),
        )
        assertEquals(emptyList<MediaStoreCandidateRecord>(), published.candidates)
    }

    @Test
    fun `initial overflow, delta overflow, missing generation and invalid row fail closed`() {
        val initialOverflow = GateKMediaStoreSessionBaseline().beginSession(
            floorEpochMs = 1_000L,
            existingRecords = listOf(
                record(id = "a", generation = 1L),
                record(id = "b", generation = 2L),
            ),
            versionSnapshot = version(),
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
            versionSnapshot = version(),
        )
        val overflow = baseline.queryNewRecords(
            notificationUri = null,
            queriedRecords = (2L..130L).map { generation ->
                record(id = "id-$generation", generation = generation)
            },
            versionSnapshot = version(),
        )
        assertEquals(GateKMediaStoreBaselineFailure.DELTA_QUERY_OVERFLOW, overflow.failure)
        assertTrue(overflow.candidates.isEmpty())
        assertEquals(1L, baseline.currentHighWaterGeneration)

        val blocked = baseline.queryNewRecords(
            notificationUri = null,
            queriedRecords = listOf(record(id = "new", generation = 2L)),
            versionSnapshot = version(),
        )
        assertEquals(GateKMediaStoreBaselineFailure.DELTA_QUERY_OVERFLOW, blocked.failure)

        val missingGenerationBaseline = GateKMediaStoreSessionBaseline()
        missingGenerationBaseline.beginSession(
            floorEpochMs = 1_000L,
            existingRecords = listOf(record(id = "old", generation = 1L)),
            versionSnapshot = version(),
        )
        val missing = missingGenerationBaseline.queryNewRecords(
            notificationUri = null,
            queriedRecords = listOf(record(id = "missing", generation = null)),
            versionSnapshot = version(),
        )
        assertEquals(GateKMediaStoreBaselineFailure.MISSING_GENERATION, missing.failure)
        assertTrue(missing.candidates.isEmpty())

        val invalidBaseline = GateKMediaStoreSessionBaseline()
        invalidBaseline.beginSession(
            floorEpochMs = 1_000L,
            existingRecords = listOf(record(id = "old", generation = 1L)),
            versionSnapshot = version(),
        )
        val invalid = invalidBaseline.queryNewRecords(
            notificationUri = null,
            queriedRecords = listOf(record(id = "", generation = 2L)),
            versionSnapshot = version(),
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
            versionSnapshot = version(),
        )

        val result = baseline.queryNewRecords(
            notificationUri = null,
            queriedRecords = listOf(
                record(id = "new-3", generation = 3L),
                record(id = "new-2", generation = 2L),
            ),
            versionSnapshot = version(),
        )

        assertEquals(GateKMediaStoreBaselineFailure.OUT_OF_ORDER_GENERATION, result.failure)
        assertTrue(result.candidates.isEmpty())
        assertEquals(1L, baseline.currentHighWaterGeneration)
    }

    @Test
    fun `blank or changing initial MediaStore version rejects the session`() {
        val blank = GateKMediaStoreSessionBaseline().beginSession(
            floorEpochMs = 1_000L,
            existingRecords = emptyList(),
            versionSnapshot = version(before = "", after = ""),
        )
        assertEquals(
            GateKMediaStoreBaselineStartResult.Rejected(
                GateKMediaStoreBaselineFailure.MEDIA_STORE_VERSION_UNAVAILABLE,
            ),
            blank,
        )

        val changed = GateKMediaStoreSessionBaseline().beginSession(
            floorEpochMs = 1_000L,
            existingRecords = emptyList(),
            versionSnapshot = version(before = "media-store-v1", after = "media-store-v2"),
        )
        assertEquals(
            GateKMediaStoreBaselineStartResult.Rejected(
                GateKMediaStoreBaselineFailure.MEDIA_STORE_VERSION_CHANGED,
            ),
            changed,
        )
    }

    @Test
    fun `delta version mismatch blocks without advancing high water and end clears session`() {
        val baseline = GateKMediaStoreSessionBaseline()
        baseline.beginSession(
            floorEpochMs = 1_000L,
            existingRecords = listOf(record(id = "old", generation = 1L)),
            versionSnapshot = version(),
        )

        val result = baseline.queryNewRecords(
            notificationUri = null,
            queriedRecords = listOf(record(id = "new", generation = 2L)),
            versionSnapshot = version(before = "media-store-v2", after = "media-store-v2"),
        )

        assertEquals(GateKMediaStoreBaselineFailure.MEDIA_STORE_VERSION_CHANGED, result.failure)
        assertTrue(result.candidates.isEmpty())
        assertEquals(1L, baseline.currentHighWaterGeneration)
        baseline.endSession()
        assertFalse(baseline.isActive)
        assertEquals(null, baseline.currentMediaStoreVersion)
    }

    @Test
    fun `delta pre-post version race fails closed`() {
        val baseline = GateKMediaStoreSessionBaseline()
        baseline.beginSession(
            floorEpochMs = 1_000L,
            existingRecords = listOf(record(id = "old", generation = 1L)),
            versionSnapshot = version(),
        )

        val result = baseline.queryNewRecords(
            notificationUri = null,
            queriedRecords = listOf(record(id = "new", generation = 2L)),
            versionSnapshot = version(before = "media-store-v1", after = "media-store-v2"),
        )

        assertEquals(GateKMediaStoreBaselineFailure.MEDIA_STORE_VERSION_CHANGED, result.failure)
        assertEquals(1L, baseline.currentHighWaterGeneration)
    }

    @Test
    fun `row created before session cannot pass when it is published after session`() {
        val baseline = GateKMediaStoreSessionBaseline()
        baseline.beginSession(
            floorEpochMs = 10_500L,
            existingRecords = emptyList(),
            versionSnapshot = version(),
        )

        val publishedPendingRow = record(
            id = "pending-before-session",
            generation = 2L,
            dateAddedSec = 9L,
            dateModifiedSec = 12L,
        )
        val result = baseline.queryNewRecords(
            notificationUri = null,
            queriedRecords = listOf(publishedPendingRow),
            versionSnapshot = version(),
        )

        assertEquals(emptyList<MediaStoreCandidateRecord>(), result.candidates)
        assertEquals(null, result.failure)
        assertEquals(2L, baseline.currentHighWaterGeneration)
    }

    private fun record(
        id: String,
        generation: Long?,
        dateAddedSec: Long = 100L,
        dateModifiedSec: Long = 0L,
    ): MediaStoreCandidateRecord = MediaStoreCandidateRecord(
        mediaId = id,
        generation = generation,
        dateAddedEpochSec = dateAddedSec,
        dateModifiedEpochSec = dateModifiedSec,
        metadata = MediaStoreImageMetadata(
            uri = "content://media/external/images/media/${id.ifBlank { "invalid" }}",
            relativePath = "Pictures/Screenshots/",
            mimeType = "image/png",
            width = 1080,
            height = 1920,
        ),
    )

    private fun version(
        before: String = "media-store-v1",
        after: String = before,
    ) = GateKMediaStoreVersionSnapshot(
        mediaStoreVersionBefore = before,
        mediaStoreVersionAfter = after,
    )
}
