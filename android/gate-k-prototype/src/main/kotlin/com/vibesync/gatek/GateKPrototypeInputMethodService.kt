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
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicBoolean

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
    private val attemptUiState = GateKAttemptUiState()
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
    @Volatile
    private var startAttemptButton: Button? = null

    override fun onCreateInputView(): View {
        val button = Button(this).apply {
            text = "Start Gate K attempt"
            contentDescription = "Start Gate K attempt"
            isEnabled = false
            setOnClickListener { startAttemptFromUi() }
        }
        startAttemptButton = button
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(TextView(context).apply {
                text = "Gate K screenshot prototype"
                contentDescription = "Gate K screenshot prototype"
            })
            addView(button, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ))
        }
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        finishActiveSession()
        setStartAttemptButtonEnabled(false)

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
            attemptUiState.onSessionShown(sessionId)
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
        setStartAttemptButtonEnabled(false)
        val sessionId = activeSessionId ?: run {
            mediaStoreBaseline.endSession()
            unregisterMediaStoreObserver()
            return
        }
        attemptUiState.onSessionHidden(sessionId)
        // A normalized equal-millisecond floor can be ahead of wall time;
        // clamp the service lifecycle event so normal cleanup still reaches
        // the pipeline/dedupe, while the public floor seam rejects gross
        // out-of-order events in isolation.
        val hiddenAtEpochMs = maxOf(
            System.currentTimeMillis(),
            activeSessionFloorEpochMs ?: 0L,
        )
        synchronized(pipelineLock) {
            pipeline.onImeHidden(
                ImeSessionEnd(
                    sessionId = sessionId,
                    imeHiddenAtEpochMs = hiddenAtEpochMs,
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

    private fun setStartAttemptButtonEnabled(enabled: Boolean) {
        val update = {
            startAttemptButton?.isEnabled = enabled
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            update()
        } else {
            mainHandler.post(update)
        }
    }

    private fun markObserverNotReadyAndDisable(sessionId: String) {
        attemptCoordinator.markObserverNotReady(sessionId)
        attemptUiState.onObserverNotReady(sessionId)
        setStartAttemptButtonEnabled(false)
    }

    private fun markObserverReadyAndEnable(sessionId: String): Boolean {
        val floorEpochMs = activeSessionFloorEpochMs
            ?: return false
        val floorEpochSec = floorEpochMs / 1_000L
        val nowEpochMs = System.currentTimeMillis()
        if (nowEpochMs / 1_000L <= floorEpochSec) {
            // DATE_ADDED is second-granular. Keep the public attempt seam
            // locked until a source second strictly after the session floor,
            // then retry readiness on the MediaStore worker.
            val nextSecondEpochMs = if (floorEpochSec >= Long.MAX_VALUE / 1_000L) {
                Long.MAX_VALUE
            } else {
                (floorEpochSec + 1L) * 1_000L
            }
            val delayMs = (nextSecondEpochMs - nowEpochMs).coerceAtLeast(1L)
            mainHandler.postDelayed({
                try {
                    mediaStoreExecutor.execute {
                        if (activeSessionId == sessionId) {
                            markObserverReadyAndEnable(sessionId)
                        }
                    }
                } catch (_: RuntimeException) {
                    // The service is shutting down; readiness remains false.
                }
            }, delayMs)
            return true
        }
        if (!attemptCoordinator.markObserverReady(sessionId)) return false
        if (!attemptUiState.onObserverReady(sessionId)) {
            markObserverNotReadyAndDisable(sessionId)
            return false
        }
        mainHandler.post {
            val ready = activeSessionId == sessionId
                && attemptCoordinator.isObserverReady
                && attemptUiState.isEnabled(sessionId)
            startAttemptButton?.isEnabled = ready
        }
        return true
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
            val baselineStart = mediaStoreBaseline.beginSession(
                floorEpochMs = floorEpochMs,
                existingRecords = baselineQuery.records,
                initialHighWaterGeneration = baselineQuery.highWaterGeneration,
                versionSnapshot = baselineQuery.versionSnapshot
                    ?: GateKMediaStoreVersionSnapshot("", ""),
            )
            if (baselineStart !is GateKMediaStoreBaselineStartResult.Started) {
                val failure = (baselineStart as GateKMediaStoreBaselineStartResult.Rejected).failure
                markObserverNotReadyAndDisable(sessionId)
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
                    markObserverNotReadyAndDisable(sessionId)
                    mediaStoreBaseline.endSession()
                    return@execute
                }
                // A bounded delta query closes the register/query race before
                // the public attempt seam is unlocked.
                if (!observeMediaStoreNotification(null, sessionId)) {
                    unregisterMediaStoreObserver()
                    markObserverNotReadyAndDisable(sessionId)
                    mediaStoreBaseline.endSession()
                    return@execute
                }
                if (!markObserverReadyAndEnable(sessionId)) {
                    unregisterMediaStoreObserver()
                    mediaStoreBaseline.endSession()
                    return@execute
                }
            } catch (_: SecurityException) {
                // A missing/revoked grant is a fail-closed observation failure.
                contentObserver = null
                markObserverNotReadyAndDisable(sessionId)
                recordFailure(
                    sessionId = sessionId,
                    failureReason = "MEDIASTORE_GRANT_REVOKED",
                    sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
                )
                mediaStoreBaseline.endSession()
            } catch (_: RuntimeException) {
                contentObserver = null
                markObserverNotReadyAndDisable(sessionId)
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
        if (!attemptCoordinator.isObserverReady || !attemptUiState.isEnabled(sessionId)) {
            return GateKAttemptStartResult.RejectedObserverNotReady
        }
        setStartAttemptButtonEnabled(false)
        val armAllowed = AtomicBoolean(true)
        val future = try {
            mediaStoreExecutor.submit<GateKAttemptStartResult> {
                if (!armAllowed.get()
                    || activeSessionId != sessionId
                    || !attemptCoordinator.isObserverReady
                    || !attemptUiState.isEnabled(sessionId)
                ) {
                    return@submit GateKAttemptStartResult.RejectedObserverNotReady
                }
                if (attemptCoordinator.hasActiveAttempt) {
                    return@submit GateKAttemptStartResult.RejectedActiveAttempt
                }

                // This is the same serial MediaStore worker that receives
                // observer callbacks: drain a real bounded delta query first,
                // update the baseline, then capture the post-drain fence and
                // arm the attempt without any active attempt in between.
                val mediaStoreFence = GateKAttemptArmFence(
                    drainRaceClosingDelta = {
                        armAllowed.get() && observeMediaStoreNotification(null, sessionId)
                    },
                    captureCurrentFence = {
                        mediaStoreBaseline.currentAttemptFence()
                    },
                ).captureAfterDrain()
                if (!armAllowed.get() || mediaStoreFence == null) {
                    return@submit GateKAttemptStartResult.RejectedObserverNotReady
                }
                if (attemptCoordinator.hasActiveAttempt) {
                    return@submit GateKAttemptStartResult.RejectedActiveAttempt
                }

                val result = attemptCoordinator.begin(
                    attemptId = GateKAttemptId(attemptId),
                    sessionId = sessionId,
                    monotonicStart = SystemClock.elapsedRealtime(),
                    mediaStoreFence = mediaStoreFence,
                )
                if (result is GateKAttemptStartResult.Started) {
                    scheduleAttemptTimeout(result.attempt)
                }
                result
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            null
        }
        val result = if (future == null) {
            null
        } else {
            try {
                future.get(1L, TimeUnit.SECONDS)
            } catch (error: InterruptedException) {
                Thread.currentThread().interrupt()
                armAllowed.set(false)
                future.cancel(true)
                null
            } catch (_: TimeoutException) {
                armAllowed.set(false)
                future.cancel(true)
                null
            } catch (_: java.util.concurrent.ExecutionException) {
                armAllowed.set(false)
                future.cancel(true)
                null
            }
        }
        if (result == null) {
            markObserverNotReadyAndDisable(sessionId)
            return GateKAttemptStartResult.RejectedObserverNotReady
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
            markObserverNotReadyAndDisable(sessionId)
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
            markObserverNotReadyAndDisable(sessionId)
            mediaStoreBaseline.endSession()
            return false
        }
        if (activeSessionId != sessionId) return false
        val candidatesResult = mediaStoreBaseline.queryNewRecords(
            notificationUri = notificationUri?.toString(),
            queriedRecords = query.records,
            versionSnapshot = query.versionSnapshot
                ?: GateKMediaStoreVersionSnapshot("", ""),
            queriedHighWaterGeneration = query.highWaterGeneration,
        )
        if (candidatesResult.failure != null) {
            recordFailure(
                sessionId = sessionId,
                failureReason = candidatesResult.failure.name,
                sessionOutcome = GateKSessionOutcome.NOT_EVALUATED,
            )
            markObserverNotReadyAndDisable(sessionId)
            mediaStoreBaseline.endSession()
            return false
        }
        val candidates = candidatesResult.candidates
        candidates.forEach { record ->
            if (activeSessionId != sessionId) return@forEach
            val classification = MediaStoreScreenshotClassifier.classify(record.metadata)
            if (classification != MediaStoreScreenshotDecision.MediaStoreScreenshot) return@forEach
            val candidateIdentity = record.generation?.let { generation ->
                GateKMediaStoreCandidateIdentity(
                    mediaId = record.mediaId,
                    generation = generation,
                )
            } ?: return@forEach
            // A row is meaningful only while an explicit attempt is active.
            // This prevents a late A callback from filling the pipeline hash
            // set before B is armed, and quarantines rows at or below B's
            // worker-serialized generation fence before opening any bytes.
            if (!attemptCoordinator.isCandidateEligible(candidateIdentity)) return@forEach

            val content = openTransientContent(Uri.parse(record.metadata.uri))
            if (content == null) {
                recordTrial(
                    sessionId = sessionId,
                    detectedAtElapsedRealtimeMs = SystemClock.elapsedRealtime(),
                    sessionOutcome = GateKSessionOutcome.ACCEPTED,
                    dedupeOutcome = GateKDedupeOutcome.NOT_EVALUATED,
                    failureReason = "CONTENT_UNAVAILABLE",
                    candidateIdentity = candidateIdentity,
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
            recordPipelineResult(
                result = result,
                observedAtElapsedRealtimeMs = SystemClock.elapsedRealtime(),
                sessionId = sessionId,
                candidateIdentity = candidateIdentity,
            )
        }
        true
    }

    private data class MediaStoreQueryResult(
        val records: List<MediaStoreCandidateRecord> = emptyList(),
        val failureReason: String? = null,
        val versionSnapshot: GateKMediaStoreVersionSnapshot? = null,
        val highWaterGeneration: Long? = null,
    )

    private class MediaStoreQueryContractException(
        val reason: GateKMediaStoreBaselineFailure,
    ) : RuntimeException()

    private fun readMediaStoreVersion(): String? = try {
        MediaStore.getVersion(this@GateKPrototypeInputMethodService)
            .takeIf { it.isNotBlank() }
    } catch (_: RuntimeException) {
        null
    }

    private fun queryMediaStoreRecords(spec: GateKMediaStoreQuerySpec): MediaStoreQueryResult {
        val versionBefore = readMediaStoreVersion()
            ?: return MediaStoreQueryResult(
                failureReason = GateKMediaStoreBaselineFailure.MEDIA_STORE_VERSION_UNAVAILABLE.name,
            )
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
            var highestGeneration = 0L
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
                if (idIndex < 0 || dateAddedIndex < 0 || generationIndex < 0 || pendingIndex < 0) {
                    throw MediaStoreQueryContractException(
                        if (pendingIndex < 0) {
                            GateKMediaStoreBaselineFailure.INVALID_RECORD
                        } else {
                            GateKMediaStoreBaselineFailure.MISSING_GENERATION
                        },
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
                        if (cursor.getIntOrZero(pendingIndex) != 0) continue
                        // Only rows returned by the explicit IS_PENDING=0
                        // query may advance the generation fence. A pending
                        // provider row must not be treated as observed.
                        highestGeneration = maxOf(highestGeneration, generation)
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
            MediaStoreQueryResult(
                records = records,
                highWaterGeneration = highestGeneration.takeIf { it > 0L },
                versionSnapshot = GateKMediaStoreVersionSnapshot(
                    mediaStoreVersionBefore = versionBefore,
                    mediaStoreVersionAfter = readMediaStoreVersion().orEmpty(),
                ),
            )
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
        candidateIdentity: GateKMediaStoreCandidateIdentity,
    ) {
        if (activeSessionId != sessionId) return
        val terminalResult = when (result) {
            is GateKObservationResult.Accepted -> detectActiveAttempt(
                sessionId = sessionId,
                detectedAtElapsedRealtimeMs = observedAtElapsedRealtimeMs,
                sessionOutcome = GateKSessionOutcome.ACCEPTED,
                dedupeOutcome = GateKDedupeOutcome.FIRST_SEEN,
                candidateIdentity = candidateIdentity,
            )

            is GateKObservationResult.DuplicateSuppressed -> detectActiveAttempt(
                sessionId = sessionId,
                detectedAtElapsedRealtimeMs = observedAtElapsedRealtimeMs,
                sessionOutcome = GateKSessionOutcome.ACCEPTED,
                dedupeOutcome = GateKDedupeOutcome.DUPLICATE_SUPPRESSED,
                candidateIdentity = candidateIdentity,
            )

            is GateKObservationResult.Ignored -> failActiveAttempt(
                sessionId = sessionId,
                detectedAtElapsedRealtimeMs = observedAtElapsedRealtimeMs,
                reason = GateKFailureReason.METADATA_REJECTED,
                candidateIdentity = candidateIdentity,
            )

            is GateKObservationResult.Rejected -> failActiveAttempt(
                sessionId = sessionId,
                detectedAtElapsedRealtimeMs = observedAtElapsedRealtimeMs,
                reason = GateKFailureReason.METADATA_REJECTED,
                candidateIdentity = candidateIdentity,
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
        candidateIdentity: GateKMediaStoreCandidateIdentity? = null,
    ) {
        val result = if (failureReason == null) {
            detectActiveAttempt(
                sessionId = sessionId,
                detectedAtElapsedRealtimeMs = detectedAtElapsedRealtimeMs,
                sessionOutcome = sessionOutcome,
                dedupeOutcome = dedupeOutcome,
                candidateIdentity = candidateIdentity,
            )
        } else {
            failActiveAttempt(
                sessionId = sessionId,
                detectedAtElapsedRealtimeMs = detectedAtElapsedRealtimeMs,
                reason = GateKFailureReason.fromLegacy(failureReason),
                candidateIdentity = candidateIdentity,
            )
        }
        recordTerminalResult(result)
    }

    private fun detectActiveAttempt(
        sessionId: String,
        detectedAtElapsedRealtimeMs: Long,
        sessionOutcome: GateKSessionOutcome,
        dedupeOutcome: GateKDedupeOutcome,
        candidateIdentity: GateKMediaStoreCandidateIdentity? = null,
    ): GateKAttemptTerminalResult {
        val attempt = attemptCoordinator.currentAttempt
            ?: return GateKAttemptTerminalResult.IgnoredNoActiveAttempt
        return attemptCoordinator.detected(
            attemptId = attempt.attemptId,
            sessionId = sessionId,
            detectedAtElapsedRealtimeMs = detectedAtElapsedRealtimeMs,
            sessionOutcome = sessionOutcome,
            dedupeOutcome = dedupeOutcome,
            candidateIdentity = candidateIdentity,
        )
    }

    private fun failActiveAttempt(
        sessionId: String,
        detectedAtElapsedRealtimeMs: Long,
        reason: GateKFailureReason,
        candidateIdentity: GateKMediaStoreCandidateIdentity? = null,
    ): GateKAttemptTerminalResult {
        val attempt = attemptCoordinator.currentAttempt
            ?: return GateKAttemptTerminalResult.IgnoredNoActiveAttempt
        return attemptCoordinator.failed(
            attemptId = attempt.attemptId,
            sessionId = sessionId,
            detectedAtElapsedRealtimeMs = detectedAtElapsedRealtimeMs,
            reason = reason,
            candidateIdentity = candidateIdentity,
        )
    }

    private fun recordTerminalResult(result: GateKAttemptTerminalResult) {
        if (result is GateKAttemptTerminalResult.Recorded) {
            trialRecorder.recordTerminal(result.terminal)
            if (result.terminal.state != GateKAttemptState.SUCCEEDED) {
                // Coordinator and UI both fail-stop this IME session. A
                // timeout must not be followed by a replacement attempt.
                attemptUiState.onAttemptFailed(result.terminal.sessionId)
                setStartAttemptButtonEnabled(false)
            } else {
                mainHandler.post {
                    val ready = activeSessionId == result.terminal.sessionId
                        && attemptCoordinator.isObserverReady
                        && attemptUiState.isEnabled(result.terminal.sessionId)
                    startAttemptButton?.isEnabled = ready
                }
            }
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
