package com.vibesync.gatek

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MediaStoreSessionBaselineTest {
    @Test
    fun `null and collection notifications rescan against the same session baseline`() {
        val baseline = GateKMediaStoreSessionBaseline()
        baseline.beginSession(
            floorEpochMs = 100_500L,
            existingRecords = listOf(record(id = "old", dateAddedSec = 100L)),
        )

        val newScreenshot = record(id = "new", dateAddedSec = 101L, generation = 7L)
        assertEquals(
            listOf(
                newScreenshot.copy(
                    metadata = newScreenshot.metadata.copy(observedAtEpochMs = 101_000L),
                ),
            ),
            baseline.onContentObserverNotification(
                notificationUri = null,
                queriedRecords = listOf(
                    record(id = "old", dateAddedSec = 100L),
                    newScreenshot,
                ),
            ),
        )
        assertEquals(
            emptyList<MediaStoreCandidateRecord>(),
            baseline.onContentObserverNotification(
                notificationUri = "content://media/external/images/media",
                queriedRecords = listOf(newScreenshot),
            ),
        )
    }

    @Test
    fun `date modified cannot make an old screenshot look new`() {
        val baseline = GateKMediaStoreSessionBaseline()
        baseline.beginSession(
            floorEpochMs = 10_500L,
            existingRecords = listOf(
                record(
                    id = "old-modified",
                    dateAddedSec = 10L,
                    dateModifiedSec = 99L,
                ),
            ),
        )

        val oldButModified = record(
            id = "old-modified",
            dateAddedSec = 10L,
            dateModifiedSec = 99L,
        )
        val sameSecondAsFloor = record(
            id = "new-same-second",
            dateAddedSec = 10L,
            dateModifiedSec = 11L,
        )
        assertEquals(
            listOf(sameSecondAsFloor.copy(
                metadata = sameSecondAsFloor.metadata.copy(observedAtEpochMs = 10_501L),
            )),
            baseline.onContentObserverNotification(
                notificationUri = "content://media/external/images/media/99",
                queriedRecords = listOf(oldButModified, sameSecondAsFloor),
            ),
        )
    }

    @Test
    fun `missing id or imprecise date fails closed and is not retried forever`() {
        val baseline = GateKMediaStoreSessionBaseline()
        baseline.beginSession(floorEpochMs = 1_000L, existingRecords = emptyList())

        val invalidRecords = listOf(
            record(id = "", dateAddedSec = 2L),
            record(id = "missing-date", dateAddedSec = 0L),
        )
        assertEquals(
            emptyList<MediaStoreCandidateRecord>(),
            baseline.onContentObserverNotification(null, invalidRecords),
        )
        assertEquals(
            emptyList<MediaStoreCandidateRecord>(),
            baseline.onContentObserverNotification(null, invalidRecords),
        )
        assertTrue(baseline.isActive)
    }

    private fun record(
        id: String,
        dateAddedSec: Long,
        dateModifiedSec: Long = 0L,
        generation: Long? = null,
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
}
