package com.vibesync.gatek

import android.content.ContentUris
import android.content.ContentResolver
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.MediaStore
import android.view.View
import android.view.inputmethod.EditorInfo
import android.inputmethodservice.InputMethodService
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Disposable Gate K observer prototype. It has no AI, network, quota, chat
 * text, or persistent image path; screenshot bytes exist only while hashing
 * one ContentResolver result inside the active IME session.
 */
class GateKPrototypeInputMethodService : InputMethodService() {
    private companion object {
        const val MAX_TRANSIENT_IMAGE_BYTES = 8 * 1024 * 1024
    }

    private val pipeline = GateKObservationPipeline()
    private val pipelineLock = Any()
    private val mediaStoreBaseline = GateKMediaStoreSessionBaseline()
    private val attemptCoordinator = GateKAttemptCoordinator()
    private val rawDeviceDescriptor = GateKDeviceDescriptor.fromBuild()
    private val evidenceStore by lazy(LazyThreadSafetyMode.NONE) {
        GateKEvidenceStore(filesDir)
    }
    private val trialRecorder = GateKTrialRecorder(
        deviceClass = GateKDeviceClassifier.classify(rawDeviceDescriptor),
        apiLevel = rawDeviceDescriptor.apiLevel,
        deviceModel = rawDeviceDescriptor.model,
        rawDeviceDescriptor = rawDeviceDescriptor,
    )
    private val mediaStoreExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile
    private var activeSessionId: String? = null
    @Volatile
    private var activeSessionFloorEpochMs: Long? = null
    @Volatile
    private var contentObserver: ContentObserver? = null

    override fun onCreateInputView(): View = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        addView(TextView(context).apply {
            text = "Gate K screenshot prototype"
            contentDescription = "Gate K screenshot prototype"
        })
        addView(Button(context).apply {
            text = "Start Gate K attempt"
            contentDescription = "Start Gate K attempt"
            setOnClickListener { startAttemptFromUi() }
        }, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ))
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        finishActiveSession()

        val sessionId = UUID.randomUUID().toString()
        val result = synchronized(pipelineLock) {
            pipeline.onImeShown(
                ImeSessionStart(
                    sessionId = sessionId,
                    imeShownAtEpochMs = System.currentTimeMillis(),
                ),
            )
        }
        if (result is ImeSessionStartResult.Started) {
            activeSessionId = sessionId
            activeSessionFloorEpochMs = result.window.floorEpochMs
            attemptCoordinator.onSessionShown(sessionId)
            registerMediaStoreObserverIfAllowed(sessionId, result.window.floorEpochMs)
        }
    }

    override fun onFinishInputView(info: EditorInfo?, finishingInput: Boolean) {
        finishActiveSession()
        super.onFinishInputView(info, finishingInput)
    }

    override fun onDestroy() {
        finishActiveSession()
        mainHandler.removeCallbacksAndMessages(null)
        mediaStoreExecutor.shutdown()
        super.onDestroy()
    }

    private fun finishActiveSession() {
        val sessionId = activeSessionId ?: run {
            mediaStoreBaseline.endSession()
            unregisterMediaStoreObserver()
            return
        }
        synchronized(pipelineLock) {
            pipeline.onImeHidden(
                ImeSessionEnd(
                    sessionId = sessionId,
                    imeHiddenAtEpochMs = System.currentTimeMillis(),
                ),
            )
        }
        recordTerminalResult(
            attemptCoordinator.onSessionHidden(
                sessionId = sessionId,
                nowElapsedRealtimeMs = SystemClock.elapsedRealtime(),
            ),
        )
        activeSessionId = null
        activeSessionFloorEpochMs = null
        mediaStoreBaseline.endSession()
        unregisterMediaStoreObserver()
    }

    private fun registerMediaStoreObserverIfAllowed(sessionId: String, floorEpochMs: Long) {
        if (!hasFullMediaStoreImageGrant()) {
            recordFailure(
                sessionId = sessionId,
                failureReason = "FULL_IMAGE_GRANT_UNAVAILABLE",
                sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
            )
            return
        }

        mediaStoreExecutor.execute {
            if (activeSessionId != sessionId) return@execute
            val baselineQuery = queryMediaStoreRecords(
                GateKMediaStoreQueryContract.initialBaseline(),
            )
            if (baselineQuery.failureReason != null) {
                recordFailure(
                    sessionId = sessionId,
                    failureReason = baselineQuery.failureReason,
                    sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
                )
                return@execute
            }
            if (activeSessionId != sessionId) return@execute
            val baselineStart = mediaStoreBaseline.beginSession(floorEpochMs, baselineQuery.records)
            if (baselineStart !is GateKMediaStoreBaselineStartResult.Started) {
                val failure = (baselineStart as GateKMediaStoreBaselineStartResult.Rejected).failure
                attemptCoordinator.markObserverNotReady(sessionId)
                recordFailure(
                    sessionId = sessionId,
                    failureReason = failure.name,
                    sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
                )
                mediaStoreBaseline.endSession()
                return@execute
            }

            val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
                override fun onChange(selfChange: Boolean, uri: Uri?) {
                    super.onChange(selfChange, uri)
                    // Android may provide null or a collection URI. Both are
                    // only notification hints; the active-session baseline
                    // triggers a fresh collection query off the main thread.
                    try {
                        mediaStoreExecutor.execute {
                            observeMediaStoreNotification(uri, sessionId)
                        }
                    } catch (_: RuntimeException) {
                        // The service is shutting down; no evidence is
                        // emitted after the session has been closed.
                    }
                }
            }
            try {
                contentResolver.registerContentObserver(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    true,
                    observer,
                )
                contentObserver = observer
                if (activeSessionId != sessionId) {
                    unregisterMediaStoreObserver()
                    attemptCoordinator.markObserverNotReady(sessionId)
                    mediaStoreBaseline.endSession()
                    return@execute
                }
                // A bounded delta query closes the register/query race before
                // the public attempt seam is unlocked.
                if (!observeMediaStoreNotification(null, sessionId)) {
                    unregisterMediaStoreObserver()
                    attemptCoordinator.markObserverNotReady(sessionId)
                    mediaStoreBaseline.endSession()
                    return@execute
                }
                if (!attemptCoordinator.markObserverReady(sessionId)) {
                    unregisterMediaStoreObserver()
                    mediaStoreBaseline.endSession()
                    return@execute
                }
            } catch (_: SecurityException) {
                // A missing/revoked grant is a fail-closed observation failure.
                contentObserver = null
                attemptCoordinator.markObserverNotReady(sessionId)
                recordFailure(
                    sessionId = sessionId,
                    failureReason = "MEDIASTORE_GRANT_REVOKED",
                    sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
                )
                mediaStoreBaseline.endSession()
            } catch (_: RuntimeException) {
                contentObserver = null
                attemptCoordinator.markObserverNotReady(sessionId)
                recordFailure(
                    sessionId = sessionId,
                    failureReason = "MEDIASTORE_OBSERVER_REGISTRATION_FAILED",
                    sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
                )
                mediaStoreBaseline.endSession()
            }
        }
    }

    @Synchronized
    private fun unregisterMediaStoreObserver() {
        contentObserver?.let { observer ->
            contentResolver.unregisterContentObserver(observer)
        }
        contentObserver = null
    }

    private fun hasFullMediaStoreImageGrant(): Boolean {
        val granted = android.content.pm.PackageManager.PERMISSION_GRANTED
        return GateKPermissionContract.hasFullMediaStoreImageGrant(
            apiLevel = Build.VERSION.SDK_INT,
            readMediaImagesGranted =
                checkSelfPermission(GateKPermissionContract.READ_MEDIA_IMAGES) == granted,
            readMediaVisualUserSelectedGranted = checkSelfPermission(
                GateKPermissionContract.READ_MEDIA_VISUAL_USER_SELECTED,
            ) == granted,
        )
    }

    /** Metadata-only evidence access for instrumentation; no image bytes are returned. */
    fun currentEvidencePacket(): GateKEvidencePacket = trialRecorder.evidencePacket()

    /** Deterministic in-memory JSON; callers must persist it outside this prototype. */
    fun currentEvidenceJson(): String = trialRecorder.evidenceJson()

    /** App-private export filename used by the bounded runner. */
    fun currentEvidenceFileName(): String = GateKEvidenceStore.FILE_NAME

    /** Starts an explicit attempt only after the session's observer is ready. */
    fun beginMeasurementAttempt(attemptId: String): GateKAttemptStartResult {
        val sessionId = activeSessionId ?: return GateKAttemptStartResult.RejectedNoActiveSession
        val result = attemptCoordinator.begin(
            attemptId = GateKAttemptId(attemptId),
            sessionId = sessionId,
            monotonicStart = SystemClock.elapsedRealtime(),
        )
        if (result is GateKAttemptStartResult.Started) {
            scheduleAttemptTimeout(result.attempt)
        }
        return result
    }

    private fun startAttemptFromUi() {
        beginMeasurementAttempt(UUID.randomUUID().toString())
    }

    private fun scheduleAttemptTimeout(attempt: GateKActiveAttempt) {
        val deadline = attempt.triggeredAtElapsedRealtimeMs
            .plus(GateKAttemptCoordinator.DEFAULT_MAX_ATTEMPT_LATENCY_MS)
        val delay = (deadline - SystemClock.elapsedRealtime()).coerceAtLeast(1L)
        mainHandler.postDelayed({
            when (val result = attemptCoordinator.timeout(
                attemptId = attempt.attemptId,
                sessionId = attempt.sessionId,
                nowElapsedRealtimeMs = SystemClock.elapsedRealtime(),
            )) {
                GateKAttemptTerminalResult.WaitingForDeadline ->
                    scheduleAttemptTimeout(attempt)

                else -> recordTerminalResult(result)
            }
        }, delay)
    }

    private fun observeMediaStoreNotification(notificationUri: Uri?, sessionId: String): Boolean {
        if (activeSessionId != sessionId) return false
        val highWaterGeneration = mediaStoreBaseline.currentHighWaterGeneration ?: return false
        val querySpec = try {
            GateKMediaStoreQueryContract.observerDelta(highWaterGeneration)
        } catch (_: IllegalArgumentException) {
            recordFailure(
                sessionId = sessionId,
                failureReason = GateKMediaStoreBaselineFailure.GENERATION_OVERFLOW.name,
                sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
            )
            attemptCoordinator.markObserverNotReady(sessionId)
            mediaStoreBaseline.endSession()
            return false
        }
        val query = queryMediaStoreRecords(querySpec)
        if (query.failureReason != null) {
            recordFailure(
                sessionId = sessionId,
                failureReason = query.failureReason,
                sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
            )
            attemptCoordinator.markObserverNotReady(sessionId)
            mediaStoreBaseline.endSession()
            return false
        }
        if (activeSessionId != sessionId) return false
        val candidatesResult = mediaStoreBaseline.queryNewRecords(
            notificationUri = notificationUri?.toString(),
            queriedRecords = query.records,
        )
        if (candidatesResult.failure != null) {
            recordFailure(
                sessionId = sessionId,
                failureReason = candidatesResult.failure.name,
                sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
            )
            attemptCoordinator.markObserverNotReady(sessionId)
            mediaStoreBaseline.endSession()
            return false
        }
        val candidates = candidatesResult.candidates
        candidates.forEach { record ->
            if (activeSessionId != sessionId) return@forEach
            val classification = MediaStoreScreenshotClassifier.classify(record.metadata)
            if (classification != MediaStoreScreenshotDecision.MediaStoreScreenshot) return@forEach

            val content = openTransientContent(Uri.parse(record.metadata.uri))
            if (content == null) {
                recordTrial(
                    sessionId = sessionId,
                    detectedAtElapsedRealtimeMs = SystemClock.elapsedRealtime(),
                    sessionOutcome = GateKSessionOutcome.ACCEPTED,
                    dedupeOutcome = GateKDedupeOutcome.NOT_EVALUATED,
                    failureReason = "CONTENT_UNAVAILABLE",
                )
                return@forEach
            }

            // The pipeline returns an identity/decision and never exposes
            // bytes outside this stack. The local byte array is unreachable
            // after this call; no file, log, network, or database write occurs.
            val result = synchronized(pipelineLock) {
                pipeline.observe(
                    ScreenshotCandidate(
                        sessionId = sessionId,
                        observedAtEpochMs = record.metadata.observedAtEpochMs,
                        source = ScreenshotCandidateSource.MEDIA_STORE_SCREENSHOT,
                        width = record.metadata.width,
                        height = record.metadata.height,
                        content = content,
                    ),
                )
            }
            recordPipelineResult(result, SystemClock.elapsedRealtime(), sessionId)
        }
        true
    }

    private data class MediaStoreQueryResult(
        val records: List<MediaStoreCandidateRecord> = emptyList(),
        val failureReason: String? = null,
    )

    private class MediaStoreQueryContractException(
        val reason: GateKMediaStoreBaselineFailure,
    ) : RuntimeException()

    private fun queryMediaStoreRecords(spec: GateKMediaStoreQuerySpec): MediaStoreQueryResult {
        val projection = buildList {
            add(MediaStore.Images.Media._ID)
            add(MediaStore.Images.Media.RELATIVE_PATH)
            add(MediaStore.Images.Media.MIME_TYPE)
            add(MediaStore.Images.Media.WIDTH)
            add(MediaStore.Images.Media.HEIGHT)
            add(MediaStore.Images.Media.DATE_ADDED)
            add(MediaStore.Images.Media.DATE_MODIFIED)
            add(MediaStore.Images.Media.IS_PENDING)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                add(MediaStore.MediaColumns.GENERATION_ADDED)
            }
        }.toTypedArray()
        return try {
            val cursor = contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                spec.toContentResolverQueryArgs(),
                null,
            ) ?: return MediaStoreQueryResult(failureReason = "MEDIASTORE_QUERY_FAILED")
            val records = cursor.use { cursor ->
                val idIndex = cursor.getColumnIndex(MediaStore.Images.Media._ID)
                val relativePathIndex = cursor.getColumnIndex(MediaStore.Images.Media.RELATIVE_PATH)
                val mimeTypeIndex = cursor.getColumnIndex(MediaStore.Images.Media.MIME_TYPE)
                val widthIndex = cursor.getColumnIndex(MediaStore.Images.Media.WIDTH)
                val heightIndex = cursor.getColumnIndex(MediaStore.Images.Media.HEIGHT)
                val dateAddedIndex = cursor.getColumnIndex(MediaStore.Images.Media.DATE_ADDED)
                val dateModifiedIndex = cursor.getColumnIndex(MediaStore.Images.Media.DATE_MODIFIED)
                val pendingIndex = cursor.getColumnIndex(MediaStore.Images.Media.IS_PENDING)
                val generationIndex = cursor.getColumnIndex(MediaStore.MediaColumns.GENERATION_ADDED)
                if (idIndex < 0 || dateAddedIndex < 0 || generationIndex < 0) {
                    throw MediaStoreQueryContractException(
                        GateKMediaStoreBaselineFailure.MISSING_GENERATION,
                    )
                }
                buildList {
                    var previousGeneration = 0L
                    var rowsSeen = 0
                    while (cursor.moveToNext()) {
                        rowsSeen += 1
                        if (rowsSeen > spec.maxRows) {
                            throw MediaStoreQueryContractException(
                                if (spec.phase == GateKMediaStoreQueryPhase.INITIAL_BASELINE) {
                                    GateKMediaStoreBaselineFailure.INITIAL_QUERY_OVERFLOW
                                } else {
                                    GateKMediaStoreBaselineFailure.DELTA_QUERY_OVERFLOW
                                },
                            )
                        }
                        val generation = cursor.getLongOrNull(generationIndex)
                            ?: throw MediaStoreQueryContractException(
                                GateKMediaStoreBaselineFailure.MISSING_GENERATION,
                            )
                        if (generation <= 0L) {
                            throw MediaStoreQueryContractException(
                                GateKMediaStoreBaselineFailure.INVALID_GENERATION,
                            )
                        }
                        if (generation < previousGeneration) {
                            throw MediaStoreQueryContractException(
                                GateKMediaStoreBaselineFailure.OUT_OF_ORDER_GENERATION,
                            )
                        }
                        previousGeneration = generation
                        if (pendingIndex >= 0 && cursor.getIntOrZero(pendingIndex) != 0) continue
                        val mediaId = cursor.getLongOrZero(idIndex)
                        if (mediaId <= 0L) {
                            throw MediaStoreQueryContractException(
                                GateKMediaStoreBaselineFailure.INVALID_RECORD,
                            )
                        }
                        val dateAdded = cursor.getLongOrZero(dateAddedIndex)
                        if (dateAdded <= 0L) {
                            throw MediaStoreQueryContractException(
                                GateKMediaStoreBaselineFailure.INVALID_RECORD,
                            )
                        }
                        val itemUri = ContentUris.withAppendedId(
                            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                            mediaId,
                        )
                        add(
                            MediaStoreCandidateRecord(
                                mediaId = mediaId.toString(),
                                generation = generation,
                                dateAddedEpochSec = dateAdded,
                                dateModifiedEpochSec = cursor.getLongOrZero(dateModifiedIndex),
                                metadata = MediaStoreImageMetadata(
                                    uri = itemUri.toString(),
                                    relativePath = cursor.getStringOrNull(relativePathIndex),
                                    mimeType = cursor.getStringOrNull(mimeTypeIndex),
                                    width = cursor.getIntOrZero(widthIndex),
                                    height = cursor.getIntOrZero(heightIndex),
                                ),
                            ),
                        )
                    }
                }
            }
            MediaStoreQueryResult(records = records)
        } catch (error: MediaStoreQueryContractException) {
            MediaStoreQueryResult(failureReason = error.reason.name)
        } catch (_: SecurityException) {
            MediaStoreQueryResult(failureReason = "MEDIASTORE_GRANT_REVOKED")
        } catch (_: RuntimeException) {
            MediaStoreQueryResult(failureReason = "MEDIASTORE_QUERY_FAILED")
        }
    }

    private fun recordPipelineResult(
        result: GateKObservationResult,
        observedAtElapsedRealtimeMs: Long,
        sessionId: String,
    ) {
        if (activeSessionId != sessionId) return
        val terminalResult = when (result) {
            is GateKObservationResult.Accepted -> detectActiveAttempt(
                sessionId = sessionId,
                detectedAtElapsedRealtimeMs = observedAtElapsedRealtimeMs,
                sessionOutcome = GateKSessionOutcome.ACCEPTED,
                dedupeOutcome = GateKDedupeOutcome.FIRST_SEEN,
            )

            is GateKObservationResult.DuplicateSuppressed -> detectActiveAttempt(
                sessionId = sessionId,
                detectedAtElapsedRealtimeMs = observedAtElapsedRealtimeMs,
                sessionOutcome = GateKSessionOutcome.ACCEPTED,
                dedupeOutcome = GateKDedupeOutcome.DUPLICATE_SUPPRESSED,
            )

            is GateKObservationResult.Ignored -> failActiveAttempt(
                sessionId = sessionId,
                detectedAtElapsedRealtimeMs = observedAtElapsedRealtimeMs,
                reason = GateKFailureReason.METADATA_REJECTED,
            )

            is GateKObservationResult.Rejected -> failActiveAttempt(
                sessionId = sessionId,
                detectedAtElapsedRealtimeMs = observedAtElapsedRealtimeMs,
                reason = GateKFailureReason.METADATA_REJECTED,
            )
        }
        recordTerminalResult(terminalResult)
    }

    private fun recordFailure(
        sessionId: String,
        failureReason: String,
        sessionOutcome: GateKSessionOutcome,
    ) {
        if (activeSessionId != sessionId) return
        val result = failActiveAttempt(
            sessionId = sessionId,
            detectedAtElapsedRealtimeMs = SystemClock.elapsedRealtime(),
            reason = GateKFailureReason.fromLegacy(failureReason),
        )
        recordTerminalResult(result)
    }

    private fun recordTrial(
        sessionId: String,
        detectedAtElapsedRealtimeMs: Long,
        sessionOutcome: GateKSessionOutcome,
        dedupeOutcome: GateKDedupeOutcome,
        failureReason: String?,
    ) {
        val result = if (failureReason == null) {
            detectActiveAttempt(
                sessionId = sessionId,
                detectedAtElapsedRealtimeMs = detectedAtElapsedRealtimeMs,
                sessionOutcome = sessionOutcome,
                dedupeOutcome = dedupeOutcome,
            )
        } else {
            failActiveAttempt(
                sessionId = sessionId,
                detectedAtElapsedRealtimeMs = detectedAtElapsedRealtimeMs,
                reason = GateKFailureReason.fromLegacy(failureReason),
            )
        }
        recordTerminalResult(result)
    }

    private fun detectActiveAttempt(
        sessionId: String,
        detectedAtElapsedRealtimeMs: Long,
        sessionOutcome: GateKSessionOutcome,
        dedupeOutcome: GateKDedupeOutcome,
    ): GateKAttemptTerminalResult {
        val attempt = attemptCoordinator.currentAttempt
            ?: return GateKAttemptTerminalResult.IgnoredNoActiveAttempt
        return attemptCoordinator.detected(
            attemptId = attempt.attemptId,
            sessionId = sessionId,
            detectedAtElapsedRealtimeMs = detectedAtElapsedRealtimeMs,
            sessionOutcome = sessionOutcome,
            dedupeOutcome = dedupeOutcome,
        )
    }

    private fun failActiveAttempt(
        sessionId: String,
        detectedAtElapsedRealtimeMs: Long,
        reason: GateKFailureReason,
    ): GateKAttemptTerminalResult {
        val attempt = attemptCoordinator.currentAttempt
            ?: return GateKAttemptTerminalResult.IgnoredNoActiveAttempt
        return attemptCoordinator.failed(
            attemptId = attempt.attemptId,
            sessionId = sessionId,
            detectedAtElapsedRealtimeMs = detectedAtElapsedRealtimeMs,
            reason = reason,
        )
    }

    private fun recordTerminalResult(result: GateKAttemptTerminalResult) {
        if (result is GateKAttemptTerminalResult.Recorded) {
            trialRecorder.recordTerminal(result.terminal)
            try {
                mediaStoreExecutor.execute {
                    try {
                        evidenceStore.write(trialRecorder.evidencePacket())
                    } catch (_: java.io.IOException) {
                        // Evidence persistence is fail-closed; no exception
                        // text or partial file is exposed as trial metadata.
                    }
                }
            } catch (_: RuntimeException) {
                // The service is shutting down; never create a synthetic trial
                // merely because the worker cannot accept an export task.
            }
        }
    }

    private fun openTransientContent(uri: Uri): ByteArray? {
        return try {
            contentResolver.openInputStream(uri)?.use { input -> input.readBounded() }
        } catch (_: SecurityException) {
            null
        } catch (_: java.io.IOException) {
            null
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun InputStream.readBounded(): ByteArray? {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0
        while (true) {
            val read = read(buffer)
            if (read < 0) break
            total += read
            if (total > MAX_TRANSIENT_IMAGE_BYTES) return null
            output.write(buffer, 0, read)
        }
        return output.toByteArray()
    }

    private fun android.database.Cursor.getStringOrNull(index: Int): String? =
        if (index < 0 || isNull(index)) null else getString(index)

    private fun android.database.Cursor.getIntOrZero(index: Int): Int =
        if (index < 0 || isNull(index)) 0 else getInt(index)

    private fun android.database.Cursor.getLongOrZero(index: Int): Long =
        if (index < 0 || isNull(index)) 0L else getLong(index)

    private fun android.database.Cursor.getLongOrNull(index: Int): Long? =
        if (index < 0 || isNull(index)) null else getLong(index)

    private fun GateKMediaStoreQuerySpec.toContentResolverQueryArgs(): Bundle = Bundle().apply {
        putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
        putStringArray(
            ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS,
            selectionArgs.toTypedArray(),
        )
        putStringArray(ContentResolver.QUERY_ARG_SORT_COLUMNS, arrayOf(sortColumn))
        putInt(
            ContentResolver.QUERY_ARG_SORT_DIRECTION,
            if (sortAscending) {
                ContentResolver.QUERY_SORT_DIRECTION_ASCENDING
            } else {
                ContentResolver.QUERY_SORT_DIRECTION_DESCENDING
            },
        )
        putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
    }
}
