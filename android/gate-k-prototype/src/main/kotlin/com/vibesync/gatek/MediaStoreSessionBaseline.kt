package com.vibesync.gatek

/** A metadata row returned by a MediaStore session-wide rescan. */
data class MediaStoreCandidateRecord(
    val mediaId: String,
    val generation: Long? = null,
    val dateAddedEpochSec: Long,
    val dateModifiedEpochSec: Long = 0L,
    val metadata: MediaStoreImageMetadata,
)

/**
 * Keeps the pre-IME MediaStore ID baseline and exposes only newly observed
 * rows whose authoritative DATE_ADDED is not before the session floor's
 * second. The ID baseline distinguishes same-second inserts from old rows.
 *
 * ContentObserver URIs are hints rather than item identity: Android may send
 * null or a collection URI. The caller must query the collection and pass
 * the result here. DATE_ADDED is only a coarse lower bound because it has
 * second precision. DATE_MODIFIED and generation are retained as metadata for
 * evidence/debugging, but never make an old row eligible for this session.
 */
class GateKMediaStoreSessionBaseline {
    private val seenMediaIds = mutableSetOf<String>()
    private var sessionFloorEpochMs: Long? = null

    val isActive: Boolean
        get() = sessionFloorEpochMs != null

    @Synchronized
    fun beginSession(
        floorEpochMs: Long,
        existingRecords: List<MediaStoreCandidateRecord>,
    ) {
        require(floorEpochMs >= 0L) { "session floor must not be negative" }
        seenMediaIds.clear()
        existingRecords.forEach { record ->
            if (record.mediaId.isNotBlank()) {
                seenMediaIds += record.mediaId
            }
        }
        sessionFloorEpochMs = floorEpochMs
    }

    /**
     * Returns newly inserted rows after any observer notification. A null or
     * collection URI intentionally has the same behavior as an item URI:
     * re-query first, then apply this baseline. Invalid rows are marked seen
     * for the current session so repeated callbacks cannot manufacture data.
     */
    @Synchronized
    fun onContentObserverNotification(
        notificationUri: String?,
        queriedRecords: List<MediaStoreCandidateRecord>,
    ): List<MediaStoreCandidateRecord> {
        // The URI is deliberately not parsed: Android does not guarantee an
        // item URI, and all authority comes from the queried row metadata.
        @Suppress("UNUSED_VARIABLE")
        val ignoredNotificationUri = notificationUri
        val floorEpochMs = sessionFloorEpochMs ?: return emptyList()
        val candidates = mutableListOf<MediaStoreCandidateRecord>()
        queriedRecords.forEach { record ->
            if (record.mediaId.isBlank() || !seenMediaIds.add(record.mediaId)) {
                return@forEach
            }
            val dateAddedEpochMs = record.dateAddedEpochSec.toEpochMsOrNull() ?: return@forEach
            // A new row in the floor's same second is eligible only because
            // its stable MediaStore ID was absent from the pre-session query.
            // This avoids losing real screenshots to second-vs-millisecond
            // precision while the baseline prevents an old row from replaying.
            if (record.dateAddedEpochSec < floorEpochMs / 1_000L) return@forEach
            if (floorEpochMs == Long.MAX_VALUE) return@forEach
            candidates += record.copy(
                metadata = record.metadata.copy(
                    observedAtEpochMs = maxOf(dateAddedEpochMs, floorEpochMs + 1L),
                ),
            )
        }
        return candidates
    }

    @Synchronized
    fun endSession() {
        sessionFloorEpochMs = null
        seenMediaIds.clear()
    }

    private fun Long.toEpochMsOrNull(): Long? {
        if (this <= 0L || this > Long.MAX_VALUE / 1_000L) return null
        return this * 1_000L
    }
}
