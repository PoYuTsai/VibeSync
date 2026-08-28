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
    MEDIA_STORE_VERSION_UNAVAILABLE,
    MEDIA_STORE_VERSION_CHANGED,
    INITIAL_QUERY_OVERFLOW,
    DELTA_QUERY_OVERFLOW,
    MISSING_GENERATION,
    INVALID_GENERATION,
    OUT_OF_ORDER_GENERATION,
    GENERATION_OVERFLOW,
    INVALID_RECORD,
}

/**
 * Version sampled around one bounded MediaStore query. Android documents that
 * GENERATION_ADDED values are only comparable while the provider version is
 * unchanged, so a blank or changing version invalidates the observation.
 */
data class GateKMediaStoreVersionSnapshot(
    val mediaStoreVersionBefore: String,
    val mediaStoreVersionAfter: String,
) {
    fun failureAgainst(expectedVersion: String? = null): GateKMediaStoreBaselineFailure? = when {
        mediaStoreVersionBefore.isBlank() || mediaStoreVersionAfter.isBlank() ->
            GateKMediaStoreBaselineFailure.MEDIA_STORE_VERSION_UNAVAILABLE

        mediaStoreVersionBefore != mediaStoreVersionAfter ->
            GateKMediaStoreBaselineFailure.MEDIA_STORE_VERSION_CHANGED

        expectedVersion != null && mediaStoreVersionAfter != expectedVersion ->
            GateKMediaStoreBaselineFailure.MEDIA_STORE_VERSION_CHANGED

        else -> null
    }
}

/** Generation fence captured immediately before arming one measurement attempt. */
data class GateKMediaStoreAttemptFence(
    val highWaterGeneration: Long,
)

/** Identity carried with one queried MediaStore row into the attempt seam. */
data class GateKMediaStoreCandidateIdentity(
    val mediaId: String,
    val generation: Long,
)

sealed interface GateKMediaStoreBaselineStartResult {
    data class Started(
        val highWaterGeneration: Long,
        val mediaStoreVersion: String = "",
    ) : GateKMediaStoreBaselineStartResult

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
    private var mediaStoreVersion: String? = null
    private var blockedFailure: GateKMediaStoreBaselineFailure? = null

    val isActive: Boolean
        get() = sessionFloorEpochMs != null

    @get:Synchronized
    val currentHighWaterGeneration: Long?
        get() = highWaterGeneration

    @get:Synchronized
    val currentMediaStoreVersion: String?
        get() = mediaStoreVersion

    @Synchronized
    fun currentAttemptFence(): GateKMediaStoreAttemptFence? {
        if (!isActive || blockedFailure != null) return null
        return highWaterGeneration?.let { generation ->
            GateKMediaStoreAttemptFence(generation)
        }
    }

    @Synchronized
    fun beginSession(
        floorEpochMs: Long,
        existingRecords: List<MediaStoreCandidateRecord>,
        initialHighWaterGeneration: Long? = null,
        versionSnapshot: GateKMediaStoreVersionSnapshot = GateKMediaStoreVersionSnapshot(
            mediaStoreVersionBefore = "",
            mediaStoreVersionAfter = "",
        ),
    ): GateKMediaStoreBaselineStartResult {
        if (floorEpochMs < 0L) {
            return GateKMediaStoreBaselineStartResult.Rejected(
                GateKMediaStoreBaselineFailure.INVALID_INPUT,
            )
        }
        versionSnapshot.failureAgainst()?.let { failure ->
            return GateKMediaStoreBaselineStartResult.Rejected(failure)
        }
        if (existingRecords.size > GateKMediaStoreQueryContract.INITIAL_MAX_ROWS) {
            return GateKMediaStoreBaselineStartResult.Rejected(
                GateKMediaStoreBaselineFailure.INITIAL_QUERY_OVERFLOW,
            )
        }
        val initial = existingRecords.singleOrNull()
        if (initialHighWaterGeneration != null
            && initialHighWaterGeneration < 0L
        ) {
            return GateKMediaStoreBaselineStartResult.Rejected(
                GateKMediaStoreBaselineFailure.INVALID_GENERATION,
            )
        }
        if (initial != null) {
            validateRecord(initial)?.let { failure ->
                return GateKMediaStoreBaselineStartResult.Rejected(failure)
            }
        }
        val initialGeneration = initial?.generation ?: 0L
        val highWaterGeneration = initialHighWaterGeneration ?: initialGeneration
        if (highWaterGeneration < initialGeneration) {
            return GateKMediaStoreBaselineStartResult.Rejected(
                GateKMediaStoreBaselineFailure.INVALID_GENERATION,
            )
        }
        if (highWaterGeneration == Long.MAX_VALUE) {
            return GateKMediaStoreBaselineStartResult.Rejected(
                GateKMediaStoreBaselineFailure.GENERATION_OVERFLOW,
            )
        }
        seenMediaIds.clear()
        initial?.let { seenMediaIds += it.mediaId }
        sessionFloorEpochMs = floorEpochMs
        this.highWaterGeneration = highWaterGeneration
        mediaStoreVersion = versionSnapshot.mediaStoreVersionAfter
        blockedFailure = null
        return GateKMediaStoreBaselineStartResult.Started(
            highWaterGeneration = highWaterGeneration,
            mediaStoreVersion = versionSnapshot.mediaStoreVersionAfter,
        )
    }

    /** Convenience overload for a provider version already sampled as stable. */
    fun beginSession(
        floorEpochMs: Long,
        existingRecords: List<MediaStoreCandidateRecord>,
        mediaStoreVersion: String,
    ): GateKMediaStoreBaselineStartResult = beginSession(
        floorEpochMs = floorEpochMs,
        existingRecords = existingRecords,
        versionSnapshot = GateKMediaStoreVersionSnapshot(
            mediaStoreVersionBefore = mediaStoreVersion,
            mediaStoreVersionAfter = mediaStoreVersion,
        ),
    )

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
        versionSnapshot: GateKMediaStoreVersionSnapshot = GateKMediaStoreVersionSnapshot(
            mediaStoreVersionBefore = "",
            mediaStoreVersionAfter = "",
        ),
        queriedHighWaterGeneration: Long? = null,
    ): GateKMediaStoreObservationResult {
        // URI is only a notification hint. Authority comes from queried row
        // metadata, not from a caller-provided URI or source enum.
        @Suppress("UNUSED_VARIABLE")
        val ignoredNotificationUri = notificationUri
        if (!isActive) return GateKMediaStoreObservationResult()
        blockedFailure?.let { failure ->
            return GateKMediaStoreObservationResult(failure = failure)
        }
        versionSnapshot.failureAgainst(expectedVersion = mediaStoreVersion)?.let { failure ->
            return block(failure)
        }
        if (queriedRecords.size > GateKMediaStoreQueryContract.DELTA_MAX_ROWS) {
            return block(GateKMediaStoreBaselineFailure.DELTA_QUERY_OVERFLOW)
        }
        val floorEpochMs = sessionFloorEpochMs ?: return GateKMediaStoreObservationResult()
        // DATE_ADDED is second-granularity. Compare in the same unit as the
        // source instead of against a millisecond floor; DATE_MODIFIED is not
        // an eligibility signal because an old image can be touched later.
        val sessionFloorEpochSec = floorEpochMs / 1_000L
        val previousGeneration = highWaterGeneration ?: return block(
            GateKMediaStoreBaselineFailure.INVALID_INPUT,
        )
        if (queriedHighWaterGeneration != null
            && (queriedHighWaterGeneration < previousGeneration
                || queriedHighWaterGeneration < 0L)
        ) {
            return block(GateKMediaStoreBaselineFailure.INVALID_GENERATION)
        }
        if (queriedHighWaterGeneration == Long.MAX_VALUE) {
            return block(GateKMediaStoreBaselineFailure.GENERATION_OVERFLOW)
        }
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
            if (record.dateAddedEpochSec <= sessionFloorEpochSec) {
                // A row created before the session may have been pending and
                // only become visible after publication. Quarantine it even
                // when its modified timestamp is newer. DATE_ADDED is only
                // second-granular, so an equal source second is not provably
                // after the session floor either.
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
        highWaterGeneration = maxOf(lastQueryGeneration, queriedHighWaterGeneration ?: previousGeneration)
        return GateKMediaStoreObservationResult(candidates = candidates)
    }

    /** Convenience overload for a provider version already sampled as stable. */
    fun queryNewRecords(
        notificationUri: String?,
        queriedRecords: List<MediaStoreCandidateRecord>,
        mediaStoreVersion: String,
        queriedHighWaterGeneration: Long? = null,
    ): GateKMediaStoreObservationResult = queryNewRecords(
        notificationUri = notificationUri,
        queriedRecords = queriedRecords,
        versionSnapshot = GateKMediaStoreVersionSnapshot(
            mediaStoreVersionBefore = mediaStoreVersion,
            mediaStoreVersionAfter = mediaStoreVersion,
        ),
        queriedHighWaterGeneration = queriedHighWaterGeneration,
    )

    @Synchronized
    fun endSession() {
        sessionFloorEpochMs = null
        highWaterGeneration = null
        mediaStoreVersion = null
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
