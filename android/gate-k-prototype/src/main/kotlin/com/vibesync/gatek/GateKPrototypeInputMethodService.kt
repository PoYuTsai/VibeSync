package com.vibesync.gatek

import android.content.ContentUris
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.View
import android.view.inputmethod.EditorInfo
import android.inputmethodservice.InputMethodService
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
    private val trialRecorder = GateKTrialRecorder(
        deviceClass = GateKDeviceClass.UNCLASSIFIED,
        apiLevel = Build.VERSION.SDK_INT,
        deviceModel = Build.MODEL.orEmpty(),
    )
    private val mediaStoreExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    @Volatile
    private var activeSessionId: String? = null
    @Volatile
    private var activeSessionFloorEpochMs: Long? = null
    @Volatile
    private var contentObserver: ContentObserver? = null

    override fun onCreateInputView(): View = TextView(this).apply {
        text = "Gate K screenshot prototype"
        contentDescription = "Gate K screenshot prototype"
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
            registerMediaStoreObserverIfAllowed(sessionId, result.window.floorEpochMs)
        }
    }

    override fun onFinishInputView(info: EditorInfo?, finishingInput: Boolean) {
        finishActiveSession()
        super.onFinishInputView(info, finishingInput)
    }

    override fun onDestroy() {
        finishActiveSession()
        mediaStoreExecutor.shutdownNow()
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
            val baselineQuery = queryMediaStoreRecords()
            if (baselineQuery.failureReason != null) {
                recordFailure(
                    sessionId = sessionId,
                    failureReason = baselineQuery.failureReason,
                    sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
                )
                return@execute
            }
            mediaStoreBaseline.beginSession(floorEpochMs, baselineQuery.records)

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
                    mediaStoreBaseline.endSession()
                    return@execute
                }
                // Close the register/query race: a row inserted between the
                // baseline query and observer registration is visible here.
                observeMediaStoreNotification(null, sessionId)
            } catch (_: SecurityException) {
                // A missing/revoked grant is a fail-closed observation failure.
                contentObserver = null
                recordFailure(
                    sessionId = sessionId,
                    failureReason = "MEDIASTORE_GRANT_REVOKED",
                    sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
                )
            } catch (_: RuntimeException) {
                contentObserver = null
                recordFailure(
                    sessionId = sessionId,
                    failureReason = "MEDIASTORE_OBSERVER_REGISTRATION_FAILED",
                    sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
                )
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
            readExternalStorageGranted =
                checkSelfPermission(GateKPermissionContract.READ_EXTERNAL_STORAGE) == granted,
        )
    }

    /** Metadata-only evidence access for instrumentation; no image bytes are returned. */
    fun currentEvidencePacket(): GateKEvidencePacket = trialRecorder.evidencePacket()

    /** Deterministic in-memory JSON; callers must persist it outside this prototype. */
    fun currentEvidenceJson(): String = trialRecorder.evidenceJson()

    private fun observeMediaStoreNotification(notificationUri: Uri?, sessionId: String) {
        if (activeSessionId != sessionId) return
        val query = queryMediaStoreRecords()
        if (query.failureReason != null) {
            recordFailure(
                sessionId = sessionId,
                failureReason = query.failureReason,
                sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
            )
            return
        }
        if (activeSessionId != sessionId) return
        val candidates = mediaStoreBaseline.onContentObserverNotification(
            notificationUri = notificationUri?.toString(),
            queriedRecords = query.records,
        )
        candidates.forEach { record ->
            if (activeSessionId != sessionId) return@forEach
            val classification = MediaStoreScreenshotClassifier.classify(record.metadata)
            if (classification != MediaStoreScreenshotDecision.MediaStoreScreenshot) return@forEach

            val observedAtEpochMs = System.currentTimeMillis()
            val content = openTransientContent(Uri.parse(record.metadata.uri))
            if (content == null) {
                recordTrial(
                    sessionId = sessionId,
                    success = false,
                    latencyMs = latencyFromActiveSession(observedAtEpochMs),
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
            recordPipelineResult(result, observedAtEpochMs, sessionId)
        }
    }

    private data class MediaStoreQueryResult(
        val records: List<MediaStoreCandidateRecord> = emptyList(),
        val failureReason: String? = null,
    )

    private fun queryMediaStoreRecords(): MediaStoreQueryResult {
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
                null,
                null,
                "${MediaStore.Images.Media.DATE_ADDED} ASC",
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
                if (idIndex < 0 || dateAddedIndex < 0) {
                    throw IllegalStateException("MediaStore baseline columns are unavailable")
                }
                buildList {
                    while (cursor.moveToNext()) {
                        if (pendingIndex >= 0 && cursor.getIntOrZero(pendingIndex) != 0) continue
                        val mediaId = cursor.getLongOrZero(idIndex)
                        if (mediaId <= 0L) continue
                        val dateAdded = cursor.getLongOrZero(dateAddedIndex)
                        if (dateAdded <= 0L) continue
                        val itemUri = ContentUris.withAppendedId(
                            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                            mediaId,
                        )
                        add(
                            MediaStoreCandidateRecord(
                                mediaId = mediaId.toString(),
                                generation = cursor.getLongOrNull(generationIndex),
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
        } catch (_: SecurityException) {
            MediaStoreQueryResult(failureReason = "MEDIASTORE_GRANT_REVOKED")
        } catch (_: RuntimeException) {
            MediaStoreQueryResult(failureReason = "MEDIASTORE_QUERY_FAILED")
        }
    }

    private fun recordPipelineResult(
        result: GateKObservationResult,
        observedAtEpochMs: Long,
        sessionId: String,
    ) {
        if (activeSessionId != sessionId) return
        val latencyMs = latencyFromActiveSession(observedAtEpochMs)
        when (result) {
            is GateKObservationResult.Accepted -> recordTrial(
                sessionId = sessionId,
                success = latencyMs in 0L..GateKTrialRecorder.DEFAULT_MAX_OBSERVATION_LATENCY_MS,
                latencyMs = latencyMs,
                sessionOutcome = GateKSessionOutcome.ACCEPTED,
                dedupeOutcome = GateKDedupeOutcome.FIRST_SEEN,
                failureReason = if (
                    latencyMs in 0L..GateKTrialRecorder.DEFAULT_MAX_OBSERVATION_LATENCY_MS
                ) {
                    null
                } else {
                    "OBSERVATION_LATENCY_INVALID_OR_OVER_3S"
                },
            )

            is GateKObservationResult.DuplicateSuppressed -> recordTrial(
                sessionId = sessionId,
                success = false,
                latencyMs = latencyMs,
                sessionOutcome = GateKSessionOutcome.ACCEPTED,
                dedupeOutcome = GateKDedupeOutcome.DUPLICATE_SUPPRESSED,
                failureReason = "DUPLICATE_SUPPRESSED",
            )

            is GateKObservationResult.Ignored -> recordTrial(
                sessionId = sessionId,
                success = false,
                latencyMs = latencyMs,
                sessionOutcome = GateKSessionOutcome.IGNORED,
                dedupeOutcome = GateKDedupeOutcome.NOT_EVALUATED,
                failureReason = "IGNORED_${result.reason.name}",
            )

            is GateKObservationResult.Rejected -> recordTrial(
                sessionId = sessionId,
                success = false,
                latencyMs = latencyMs,
                sessionOutcome = GateKSessionOutcome.REJECTED,
                dedupeOutcome = GateKDedupeOutcome.NOT_EVALUATED,
                failureReason = "REJECTED_${result.reason.name}",
            )
        }
    }

    private fun recordFailure(
        sessionId: String,
        failureReason: String,
        sessionOutcome: GateKSessionOutcome,
    ) {
        if (activeSessionId != sessionId) return
        val now = System.currentTimeMillis()
        recordTrial(
            sessionId = sessionId,
            success = false,
            latencyMs = latencyFromActiveSession(now),
            sessionOutcome = sessionOutcome,
            dedupeOutcome = GateKDedupeOutcome.NOT_EVALUATED,
            failureReason = failureReason,
        )
    }

    private fun recordTrial(
        sessionId: String,
        success: Boolean,
        latencyMs: Long,
        sessionOutcome: GateKSessionOutcome,
        dedupeOutcome: GateKDedupeOutcome,
        failureReason: String?,
    ) {
        if (activeSessionId != sessionId) return
        trialRecorder.record(
            success = success,
            latencyMs = latencyMs,
            sessionOutcome = sessionOutcome,
            dedupeOutcome = dedupeOutcome,
            failureReason = failureReason,
        )
    }

    private fun latencyFromActiveSession(observedAtEpochMs: Long): Long =
        observedAtEpochMs - (activeSessionFloorEpochMs ?: observedAtEpochMs)

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
}
