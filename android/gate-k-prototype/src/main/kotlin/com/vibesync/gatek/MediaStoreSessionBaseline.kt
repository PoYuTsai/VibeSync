package com.vibesync.gatek

/**
 * Pure query description used by the disposable MediaStore scanner. Keeping
 * the selection, ordering, and limits here makes the no-full-scan contract
 * testable without an Android provider or a device.
 */
enum class GateKMediaStoreQueryPhase {
    INITIAL_BASELINE,
    OBSERVER_DELTA,
}

data class GateKMediaStoreQuerySpec(
    val phase: GateKMediaStoreQueryPhase,
    val selection: String?,
    val selectionArgs: List<String>,
    val sortColumn: String,
    val sortAscending: Boolean,
    val limit: Int,
    val maxRows: Int,
)

object GateKMediaStoreQueryContract {
    const val GENERATION_ADDED_COLUMN = "generation_added"
    const val IS_PENDING_COLUMN = "is_pending"
    const val INITIAL_MAX_ROWS = 1
    const val DELTA_MAX_ROWS = 128
    const val DELTA_QUERY_LIMIT = DELTA_MAX_ROWS + 1

    fun initialBaseline(): GateKMediaStoreQuerySpec = GateKMediaStoreQuerySpec(
        phase = GateKMediaStoreQueryPhase.INITIAL_BASELINE,
        selection = "$IS_PENDING_COLUMN = ?",
        selectionArgs = listOf("0"),
        sortColumn = GENERATION_ADDED_COLUMN,
        sortAscending = false,
        limit = INITIAL_MAX_ROWS,
        maxRows = INITIAL_MAX_ROWS,
    )

    fun observerDelta(highWaterGeneration: Long): GateKMediaStoreQuerySpec {
        require(highWaterGeneration >= 0L) {
            "generation high-water mark must not be negative"
        }
        require(highWaterGeneration < Long.MAX_VALUE) {
            "generation high-water mark overflow"
        }
        return GateKMediaStoreQuerySpec(
            phase = GateKMediaStoreQueryPhase.OBSERVER_DELTA,
            selection = "$IS_PENDING_COLUMN = ? AND $GENERATION_ADDED_COLUMN > ?",
            selectionArgs = listOf("0", highWaterGeneration.toString()),
            sortColumn = GENERATION_ADDED_COLUMN,
            sortAscending = true,
            limit = DELTA_QUERY_LIMIT,
            maxRows = DELTA_MAX_ROWS,
        )
    }
}

/** A row returned by a bounded MediaStore query. */
data class MediaStoreCandidateRecord(
    val mediaId: String,
    val generation: Long? = null,
    val dateAddedEpochSec: Long,
    val dateModifiedEpochSec: Long = 0L,
    val metadata: MediaStoreImageMetadata,
)

enum class GateKMediaStoreBaselineFailure {
    INVALID_INPUT,
    INITIAL_QUERY_OVERFLOW,
    DELTA_QUERY_OVERFLOW,
    MISSING_GENERATION,
    INVALID_GENERATION,
    OUT_OF_ORDER_GENERATION,
    GENERATION_OVERFLOW,
    INVALID_RECORD,
}

sealed interface GateKMediaStoreBaselineStartResult {
    data class Started(val highWaterGeneration: Long) : GateKMediaStoreBaselineStartResult

    data class Rejected(val failure: GateKMediaStoreBaselineFailure) :
        GateKMediaStoreBaselineStartResult
}

data class GateKMediaStoreObservationResult(
    val candidates: List<MediaStoreCandidateRecord> = emptyList(),
    val failure: GateKMediaStoreBaselineFailure? = null,
)

/**
 * Tracks only the newest generation observed before the IME session. A
 * notification is a hint; the caller supplies a bounded delta query and this
 * class accepts only rows newer than the high-water mark. It never stores a
 * full album ID list.
 */
class GateKMediaStoreSessionBaseline {
    private val seenMediaIds = mutableSetOf<String>()
    private var sessionFloorEpochMs: Long? = null
    private var highWaterGeneration: Long? = null
    private var blockedFailure: GateKMediaStoreBaselineFailure? = null

    val isActive: Boolean
        get() = sessionFloorEpochMs != null

    @get:Synchronized
    val currentHighWaterGeneration: Long?
        get() = highWaterGeneration

    @Synchronized
    fun beginSession(
        floorEpochMs: Long,
        existingRecords: List<MediaStoreCandidateRecord>,
    ): GateKMediaStoreBaselineStartResult {
        if (floorEpochMs < 0L) {
            return GateKMediaStoreBaselineStartResult.Rejected(
                GateKMediaStoreBaselineFailure.INVALID_INPUT,
            )
        }
        if (existingRecords.size > GateKMediaStoreQueryContract.INITIAL_MAX_ROWS) {
            return GateKMediaStoreBaselineStartResult.Rejected(
                GateKMediaStoreBaselineFailure.INITIAL_QUERY_OVERFLOW,
            )
        }
        val initial = existingRecords.singleOrNull()
        if (initial != null) {
            validateRecord(initial)?.let { failure ->
                return GateKMediaStoreBaselineStartResult.Rejected(failure)
            }
        }
        val initialGeneration = initial?.generation ?: 0L
        seenMediaIds.clear()
        initial?.let { seenMediaIds += it.mediaId }
        sessionFloorEpochMs = floorEpochMs
        highWaterGeneration = initialGeneration
        blockedFailure = null
        return GateKMediaStoreBaselineStartResult.Started(initialGeneration)
    }

    /**
     * Compatibility-shaped list API for callers that only need candidates.
     * Query failures return an empty list; use queryNewRecords when the caller
     * must surface the bounded failure reason to evidence.
     */
    @Synchronized
    fun onContentObserverNotification(
        notificationUri: String?,
        queriedRecords: List<MediaStoreCandidateRecord>,
    ): List<MediaStoreCandidateRecord> = queryNewRecords(
        notificationUri = notificationUri,
        queriedRecords = queriedRecords,
    ).candidates

    /** Applies one bounded, generation-ordered observer delta query. */
    @Synchronized
    fun queryNewRecords(
        notificationUri: String?,
        queriedRecords: List<MediaStoreCandidateRecord>,
    ): GateKMediaStoreObservationResult {
        // URI is only a notification hint. Authority comes from queried row
        // metadata, not from a caller-provided URI or source enum.
        @Suppress("UNUSED_VARIABLE")
        val ignoredNotificationUri = notificationUri
        if (!isActive) return GateKMediaStoreObservationResult()
        blockedFailure?.let { failure ->
            return GateKMediaStoreObservationResult(failure = failure)
        }
        if (queriedRecords.size > GateKMediaStoreQueryContract.DELTA_MAX_ROWS) {
            return block(GateKMediaStoreBaselineFailure.DELTA_QUERY_OVERFLOW)
        }
        val floorEpochMs = sessionFloorEpochMs ?: return GateKMediaStoreObservationResult()
        val previousGeneration = highWaterGeneration ?: return block(
            GateKMediaStoreBaselineFailure.INVALID_INPUT,
        )
        var lastQueryGeneration = previousGeneration
        var previousReturnedGeneration = Long.MIN_VALUE
        queriedRecords.forEach { record ->
            validateRecord(record)?.let { failure -> return block(failure) }
            val generation = record.generation ?: return block(
                GateKMediaStoreBaselineFailure.MISSING_GENERATION,
            )
            if (generation < previousReturnedGeneration) {
                return block(GateKMediaStoreBaselineFailure.OUT_OF_ORDER_GENERATION)
            }
            if (generation == Long.MAX_VALUE && generation > previousGeneration) {
                return block(GateKMediaStoreBaselineFailure.GENERATION_OVERFLOW)
            }
            previousReturnedGeneration = generation
            lastQueryGeneration = maxOf(lastQueryGeneration, generation)
        }

        val candidates = queriedRecords.mapNotNull { record ->
            val generation = record.generation ?: return@mapNotNull null
            if (generation <= previousGeneration || !seenMediaIds.add(record.mediaId)) {
                return@mapNotNull null
            }
            if (floorEpochMs == Long.MAX_VALUE) {
                return@mapNotNull null
            }
            val observedAtEpochMs = maxOf(
                record.metadata.observedAtEpochMs,
                floorEpochMs + 1L,
            )
            record.copy(
                metadata = record.metadata.copy(observedAtEpochMs = observedAtEpochMs),
            )
        }
        highWaterGeneration = lastQueryGeneration
        return GateKMediaStoreObservationResult(candidates = candidates)
    }

    @Synchronized
    fun endSession() {
        sessionFloorEpochMs = null
        highWaterGeneration = null
        blockedFailure = null
        seenMediaIds.clear()
    }

    private fun block(failure: GateKMediaStoreBaselineFailure): GateKMediaStoreObservationResult {
        blockedFailure = failure
        return GateKMediaStoreObservationResult(failure = failure)
    }

    private fun validateRecord(record: MediaStoreCandidateRecord): GateKMediaStoreBaselineFailure? {
        if (record.mediaId.isBlank() || record.metadata.uri.isBlank() || record.dateAddedEpochSec <= 0L) {
            return GateKMediaStoreBaselineFailure.INVALID_RECORD
        }
        val generation = record.generation ?: return GateKMediaStoreBaselineFailure.MISSING_GENERATION
        if (generation <= 0L) return GateKMediaStoreBaselineFailure.INVALID_GENERATION
        return null
    }
}
