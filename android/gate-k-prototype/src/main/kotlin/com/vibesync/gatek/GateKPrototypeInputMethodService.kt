package com.vibesync.gatek

import android.content.ContentUris
import android.content.ContentResolver
import android.content.res.AssetFileDescriptor
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
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
 * Reads an exact-one-row cursor without moving away from the first row before
 * its immutable snapshot has been captured. Some Cursor implementations move
 * to after-last when [moveToNext] returns false, so the snapshot must happen
 * first. A second row remains a fail-closed result.
 */
internal sealed interface GateKSingleRowCursorResult<out T> {
    data object NotFound : GateKSingleRowCursorResult<Nothing>

    data object MultipleRows : GateKSingleRowCursorResult<Nothing>

    data class Ready<T>(val value: T) : GateKSingleRowCursorResult<T>
}

internal object GateKSingleRowCursorPolicy {
    fun <T> readExactlyOne(
        moveToFirst: () -> Boolean,
        snapshot: () -> T,
        moveToNext: () -> Boolean,
    ): GateKSingleRowCursorResult<T> {
        if (!moveToFirst()) return GateKSingleRowCursorResult.NotFound
        val firstRow = snapshot()
        if (moveToNext()) return GateKSingleRowCursorResult.MultipleRows
        return GateKSingleRowCursorResult.Ready(firstRow)
    }
}

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
    private val activeReadLifecycle = GateKActiveReadLifecycle()
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

    override fun onFinishInputView(finishingInput: Boolean) {
        finishActiveSession()
        super.onFinishInputView(finishingInput)
    }

    override fun onDestroy() {
        // A stream read can occupy the sole MediaStore worker. Cancel it from
        // the lifecycle thread before shutting down that worker.
        activeReadLifecycle.onServiceDestroyed()
        finishActiveSession()
        mainHandler.removeCallbacksAndMessages(null)
        mediaStoreExecutor.shutdown()
        super.onDestroy()
    }

    private fun finishActiveSession() {
        setStartAttemptButtonEnabled(false)
        val sessionId = activeSessionId ?: run {
            activeReadLifecycle.cancelAllActiveRead()
            mediaStoreBaseline.endSession()
            unregisterMediaStoreObserver()
            return
        }
        // This must happen before the session/coordinator cleanup below: a
        // blocked InputStream must be closed outside the sole worker.
        activeReadLifecycle.onSessionHidden(sessionId)
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
                        if (activeSessionId == sessionId
                            && attemptUiState.canRetryObserverReady(
                                sessionId = sessionId,
                                baselineActive = mediaStoreBaseline.isActive,
                                observerRegistered = contentObserver != null,
                            )
                        ) {
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
                cancelMeasurementArm(attemptId, sessionId)
                future.cancel(true)
                null
            } catch (_: TimeoutException) {
                armAllowed.set(false)
                cancelMeasurementArm(attemptId, sessionId)
                future.cancel(true)
                null
            } catch (_: java.util.concurrent.ExecutionException) {
                armAllowed.set(false)
                cancelMeasurementArm(attemptId, sessionId)
                future.cancel(true)
                null
            } catch (_: java.util.concurrent.CancellationException) {
                armAllowed.set(false)
                cancelMeasurementArm(attemptId, sessionId)
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

    private fun cancelMeasurementArm(attemptId: String, sessionId: String) {
        recordTerminalResult(
            attemptCoordinator.cancelArm(
                attemptId = GateKAttemptId(attemptId),
                sessionId = sessionId,
                nowElapsedRealtimeMs = SystemClock.elapsedRealtime(),
            ),
        )
    }

    private fun startAttemptFromUi() {
        beginMeasurementAttempt(UUID.randomUUID().toString())
    }

    private fun scheduleAttemptTimeout(attempt: GateKActiveAttempt) {
        val deadline = attempt.triggeredAtElapsedRealtimeMs
            .plus(GateKAttemptCoordinator.DEFAULT_MAX_ATTEMPT_LATENCY_MS)
        val delay = (deadline - SystemClock.elapsedRealtime()).coerceAtLeast(1L)
        mainHandler.postDelayed({
            val nowElapsedRealtimeMs = SystemClock.elapsedRealtime()
            if (!GateKCandidateReadinessPolicy.isDeadlineReached(
                    triggeredAtElapsedRealtimeMs = attempt.triggeredAtElapsedRealtimeMs,
                    nowElapsedRealtimeMs = nowElapsedRealtimeMs,
                )
            ) {
                // Handler scheduling can fire a little early. Do not mark the
                // attempt cancelled until the same monotonic policy says it is
                // actually past the three-second boundary.
                scheduleAttemptTimeout(attempt)
                return@postDelayed
            }
            // Do not queue cancellation behind the potentially blocked read.
            // The coordinator timeout itself remains serialized on the worker.
            activeReadLifecycle.onAttemptDeadline(
                sessionId = attempt.sessionId,
                attemptId = attempt.attemptId.value,
            )
            // Timeout must run behind any in-flight query/open/hash on the
            // same worker. This makes the deadline a privacy boundary instead
            // of allowing the main thread to terminalize a live read midway.
            try {
                mediaStoreExecutor.execute {
                    when (val result = attemptCoordinator.timeout(
                        attemptId = attempt.attemptId,
                        sessionId = attempt.sessionId,
                        nowElapsedRealtimeMs = SystemClock.elapsedRealtime(),
                    )) {
                        GateKAttemptTerminalResult.WaitingForDeadline ->
                            scheduleAttemptTimeout(attempt)

                        else -> recordTerminalResult(result)
                    }
                }
            } catch (_: java.util.concurrent.RejectedExecutionException) {
                // Shutdown is a lifecycle boundary; do not manufacture a
                // timeout record after the worker has been rejected.
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
            when (val readiness = observeCandidateWithReadinessRetry(
                sessionId = sessionId,
                initialRecord = record,
                candidateIdentity = candidateIdentity,
            )) {
                is GateKCandidateReadinessResult.Observed -> recordPipelineResult(
                    result = readiness.result,
                    observedAtElapsedRealtimeMs = SystemClock.elapsedRealtime(),
                    sessionId = sessionId,
                    candidateIdentity = candidateIdentity,
                )

                is GateKCandidateReadinessResult.Failed -> {
                    recordTerminalResult(
                        failActiveAttempt(
                            sessionId = sessionId,
                            detectedAtElapsedRealtimeMs = SystemClock.elapsedRealtime(),
                            reason = with(GateKCandidateReadinessPolicy) {
                                readiness.failure.toGateKFailureReason()
                            },
                            candidateIdentity = candidateIdentity,
                        ),
                    )
                }

                GateKCandidateReadinessResult.DeadlineReached -> Unit

                GateKCandidateReadinessResult.SessionEnded -> Unit
            }
        }
        return true
    }

    /**
     * Rechecks one exact MediaStore row when the insert notification exposed
     * it before dimensions or readable bytes were ready. The retry runs on the
     * serialized MediaStore worker and never relaxes the public candidate
     * filter. A session/attempt ending during the wait simply aborts.
     */
    private fun deadlineReadinessProbe(
        sessionId: String,
        candidateIdentity: GateKMediaStoreCandidateIdentity,
    ): GateKCandidateReadinessProbeResult? {
        if (activeSessionId != sessionId
            || !attemptCoordinator.hasActiveAttempt
            || !attemptCoordinator.isCandidateEligible(candidateIdentity)
        ) {
            return GateKCandidateReadinessProbeResult.SessionEnded
        }
        val attempt = attemptCoordinator.currentAttempt
            ?: return GateKCandidateReadinessProbeResult.SessionEnded
        if (attempt.sessionId != sessionId) {
            return GateKCandidateReadinessProbeResult.SessionEnded
        }
        when (activeReadLifecycle.cancellationFor(sessionId, attempt.attemptId.value)) {
            GateKActiveReadCancellation.ATTEMPT_DEADLINE ->
                return GateKCandidateReadinessProbeResult.DeadlineReached

            GateKActiveReadCancellation.SESSION_HIDDEN,
            GateKActiveReadCancellation.SERVICE_DESTROYED,
            GateKActiveReadCancellation.REPLACED ->
                return GateKCandidateReadinessProbeResult.SessionEnded

            null -> Unit
        }
        return if (GateKCandidateReadinessPolicy.isDeadlineReached(
                triggeredAtElapsedRealtimeMs = attempt.triggeredAtElapsedRealtimeMs,
                nowElapsedRealtimeMs = SystemClock.elapsedRealtime(),
            )
        ) {
            GateKCandidateReadinessProbeResult.DeadlineReached
        } else {
            null
        }
    }

    private fun observeCandidateWithReadinessRetry(
        sessionId: String,
        initialRecord: MediaStoreCandidateRecord,
        candidateIdentity: GateKMediaStoreCandidateIdentity,
    ): GateKCandidateReadinessResult {
        val expectedMediaStoreVersion = mediaStoreBaseline.currentMediaStoreVersion
            ?: return GateKCandidateReadinessResult.Failed(
                GateKCandidateReadinessFailure.OBSERVER_ERROR,
            )
        var currentRecord = initialRecord
        var firstProbe = true
        val retry = GateKCandidateReadinessRetry()
        return retry.resolve {
            if (activeSessionId != sessionId
                || !attemptCoordinator.hasActiveAttempt
                || !attemptCoordinator.isCandidateEligible(candidateIdentity)
            ) {
                return@resolve GateKCandidateReadinessProbeResult.SessionEnded
            }

            if (!firstProbe) {
                deadlineReadinessProbe(
                    sessionId = sessionId,
                    candidateIdentity = candidateIdentity,
                )?.let { return@resolve it }
                when (val queryResult = queryMediaStoreCandidate(
                    initialRecord = initialRecord,
                    expectedMediaStoreVersion = expectedMediaStoreVersion,
                )) {
                    is MediaStoreCandidateQueryResult.Ready -> currentRecord = queryResult.record
                    is MediaStoreCandidateQueryResult.Retryable ->
                        return@resolve GateKCandidateReadinessProbeResult.Retryable(
                            queryResult.failure,
                        )

                    is MediaStoreCandidateQueryResult.Failed ->
                        return@resolve GateKCandidateReadinessProbeResult.Failed(
                            queryResult.failure,
                        )
                }
                if (currentRecord.mediaId != candidateIdentity.mediaId
                    || currentRecord.generation != candidateIdentity.generation
                ) {
                    return@resolve GateKCandidateReadinessProbeResult.Failed(
                        GateKCandidateReadinessFailure.METADATA_REJECTED,
                    )
                }
            }
            firstProbe = false

            deadlineReadinessProbe(
                sessionId = sessionId,
                candidateIdentity = candidateIdentity,
            )?.let { return@resolve it }
            val versionResult = GateKCandidateReadinessPolicy.classifyExpectedMediaStoreVersion(
                expectedVersion = expectedMediaStoreVersion,
                observedVersion = readMediaStoreVersion(),
            )
            if (versionResult != null) {
                return@resolve versionResult
            }

            if (MediaStoreScreenshotClassifier.classify(currentRecord.metadata)
                != MediaStoreScreenshotDecision.MediaStoreScreenshot
            ) {
                return@resolve GateKCandidateReadinessProbeResult.Failed(
                    GateKCandidateReadinessFailure.METADATA_REJECTED,
                )
            }

            // WIDTH/HEIGHT are provider metadata and can briefly be zero at
            // GENERATION_ADDED time. Requery those fields before opening any
            // bytes; this preserves the strict public filter and avoids a
            // needless full-content read on every retry.
            if (currentRecord.metadata.width <= 0 || currentRecord.metadata.height <= 0) {
                return@resolve GateKCandidateReadinessProbeResult.Retryable(
                    GateKCandidateReadinessFailure.METADATA_REJECTED,
                )
            }

            deadlineReadinessProbe(
                sessionId = sessionId,
                candidateIdentity = candidateIdentity,
            )?.let { return@resolve it }
            val attemptId = attemptCoordinator.currentAttempt
                ?.takeIf { it.sessionId == sessionId }
                ?.attemptId
                ?.value
                ?: return@resolve GateKCandidateReadinessProbeResult.SessionEnded
            val contentResult = openTransientContent(
                sessionId = sessionId,
                attemptId = attemptId,
                uri = Uri.parse(currentRecord.metadata.uri),
            )
            val readyContent = when (contentResult) {
                is TransientContentResult.Ready -> contentResult
                TransientContentResult.RetryableUnavailable ->
                    return@resolve GateKCandidateReadinessProbeResult.Retryable(
                        GateKCandidateReadinessFailure.CONTENT_UNAVAILABLE,
                    )

                TransientContentResult.Cancelled ->
                    return@resolve when (
                        activeReadLifecycle.cancellationFor(sessionId, attemptId)
                    ) {
                        GateKActiveReadCancellation.ATTEMPT_DEADLINE ->
                            GateKCandidateReadinessProbeResult.DeadlineReached

                        else -> GateKCandidateReadinessProbeResult.SessionEnded
                    }

                is TransientContentResult.Failed ->
                    return@resolve GateKCandidateReadinessProbeResult.Failed(
                        contentResult.failure,
                    )
            }
            val readLease = readyContent.lease
            val content = readyContent.bytes
            val candidate = ScreenshotCandidate(
                sessionId = sessionId,
                observedAtEpochMs = maxOf(
                    currentRecord.metadata.observedAtEpochMs,
                    initialRecord.metadata.observedAtEpochMs,
                ),
                source = ScreenshotCandidateSource.MEDIA_STORE_SCREENSHOT,
                width = currentRecord.metadata.width,
                height = currentRecord.metadata.height,
                content = content,
            )

            // Opening is synchronous. If it crossed the deadline, do not hand
            // the bytes to the hashing/dedupe pipeline; the queued timeout
            // operation will own terminalization on this same worker.
            try {
                deadlineReadinessProbe(
                    sessionId = sessionId,
                    candidateIdentity = candidateIdentity,
                )?.let { return@resolve it }
                val postOpenVersionResult =
                    GateKCandidateReadinessPolicy.classifyExpectedMediaStoreVersion(
                        expectedVersion = expectedMediaStoreVersion,
                        observedVersion = readMediaStoreVersion(),
                    )
                if (postOpenVersionResult != null) {
                    return@resolve postOpenVersionResult
                }

                // Hash preparation runs outside pipelineLock and checks the
                // lease between chunks. Only the short mutable filter/dedupe
                // commit enters the lease's linearizable final gate.
                val result = readLease.runCancellable(
                    prepare = { shouldContinue ->
                        when (
                            val preparation = synchronized(pipelineLock) {
                                pipeline.prepareObservation(candidate)
                            }
                        ) {
                            is GateKObservationPreparation.Terminal ->
                                GateKPreparedObservation.Terminal(preparation.result)

                            is GateKObservationPreparation.Accepted ->
                                pipeline.prepareAcceptedObservation(
                                    preparation,
                                    shouldContinue,
                                )?.let { identity ->
                                    GateKPreparedObservation.Ready(
                                        observation = preparation,
                                        identity = identity,
                                    )
                                }
                        }
                    },
                    commit = { prepared ->
                        synchronized(pipelineLock) {
                            pipeline.commitPreparedObservation(prepared)
                        }
                    },
                ) ?: return@resolve GateKCandidateReadinessProbeResult.SessionEnded
                return@resolve GateKCandidateReadinessPolicy.classify(result)
            } finally {
                // The pipeline retains only the SHA-256 identity. Do not let
                // transient screenshot bytes survive a cancelled/failed read.
                content.fill(0)
                activeReadLifecycle.releaseRead(readLease)
            }
        }
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

    private fun mediaStoreProjection(): Array<String> = buildList {
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

    private fun queryMediaStoreRecords(spec: GateKMediaStoreQuerySpec): MediaStoreQueryResult {
        val versionBefore = readMediaStoreVersion()
            ?: return MediaStoreQueryResult(
                failureReason = GateKMediaStoreBaselineFailure.MEDIA_STORE_VERSION_UNAVAILABLE.name,
            )
        return try {
            var highestGeneration = 0L
            val cursor = contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                mediaStoreProjection(),
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

    private sealed interface MediaStoreCandidateQueryResult {
        data class Ready(val record: MediaStoreCandidateRecord) : MediaStoreCandidateQueryResult

        /** The provider may not have made this exact row readable yet. */
        data class Retryable(
            val failure: GateKCandidateReadinessFailure,
        ) : MediaStoreCandidateQueryResult

        /** A provider/observer/identity failure must not be retried as readiness. */
        data class Failed(
            val failure: GateKCandidateReadinessFailure,
        ) : MediaStoreCandidateQueryResult
    }

    private sealed interface MediaStoreCandidateRowResult {
        data class Ready(val record: MediaStoreCandidateRecord) : MediaStoreCandidateRowResult

        data object NotFound : MediaStoreCandidateRowResult

        /** The provider returned a row that cannot be bound to the original identity. */
        data object Invalid : MediaStoreCandidateRowResult
    }

    /**
     * Requeries a single already-identified row without applying the session
     * generation high-water filter. A screenshot provider may publish the row
     * before WIDTH/HEIGHT or readable bytes are complete; the caller retries
     * this exact ID while the same attempt is active. The row identity and
     * MediaStore version still have to remain stable.
     */
    private fun queryMediaStoreCandidate(
        initialRecord: MediaStoreCandidateRecord,
        expectedMediaStoreVersion: String,
    ): MediaStoreCandidateQueryResult {
        val mediaId = initialRecord.mediaId.toLongOrNull()
            ?.takeIf { it > 0L }
            ?: return MediaStoreCandidateQueryResult.Failed(
                GateKCandidateReadinessFailure.METADATA_REJECTED,
            )
        val beforeVersionResult = GateKCandidateReadinessPolicy.classifyExpectedMediaStoreVersion(
            expectedVersion = expectedMediaStoreVersion,
            observedVersion = readMediaStoreVersion(),
        )
        if (beforeVersionResult != null) {
            val failure = (beforeVersionResult as? GateKCandidateReadinessProbeResult.Failed)
                ?.failure ?: GateKCandidateReadinessFailure.OBSERVER_ERROR
            return MediaStoreCandidateQueryResult.Failed(failure)
        }
        // Query the identified item URI directly. Collection SQL selection,
        // LIMIT, and provider-specific query-arg combinations are not needed
        // for one immutable ID and were rejected by some MediaStore providers.
        val itemUri = ContentUris.withAppendedId(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            mediaId,
        )
        return try {
            val cursor = contentResolver.query(
                itemUri,
                mediaStoreProjection(),
                null,
                null,
            ) ?: run {
                return MediaStoreCandidateQueryResult.Failed(
                    GateKCandidateReadinessFailure.QUERY_FAILED,
                )
            }
            val record = cursor.use {
                val cursorResult = GateKSingleRowCursorPolicy.readExactlyOne(
                    moveToFirst = {
                        cursor.moveToFirst()
                    },
                    snapshot = {
                        run {
                            val idIndex = cursor.getColumnIndex(MediaStore.Images.Media._ID)
                            val relativePathIndex =
                                cursor.getColumnIndex(MediaStore.Images.Media.RELATIVE_PATH)
                            val mimeTypeIndex =
                                cursor.getColumnIndex(MediaStore.Images.Media.MIME_TYPE)
                            val widthIndex = cursor.getColumnIndex(MediaStore.Images.Media.WIDTH)
                            val heightIndex = cursor.getColumnIndex(MediaStore.Images.Media.HEIGHT)
                            val dateAddedIndex =
                                cursor.getColumnIndex(MediaStore.Images.Media.DATE_ADDED)
                            val dateModifiedIndex =
                                cursor.getColumnIndex(MediaStore.Images.Media.DATE_MODIFIED)
                            val pendingIndex =
                                cursor.getColumnIndex(MediaStore.Images.Media.IS_PENDING)
                            val generationIndex =
                                cursor.getColumnIndex(MediaStore.MediaColumns.GENERATION_ADDED)
                            if (idIndex < 0
                                || dateAddedIndex < 0
                                || pendingIndex < 0
                                || generationIndex < 0
                            ) {
                                MediaStoreCandidateRowResult.Invalid
                            } else if (cursor.getIntOrZero(pendingIndex) != 0) {
                                MediaStoreCandidateRowResult.Invalid
                            } else {
                                val rowMediaId = cursor.getLongOrZero(idIndex)
                                val generation = cursor.getLongOrNull(generationIndex)
                                val dateAdded = cursor.getLongOrZero(dateAddedIndex)
                                if (rowMediaId <= 0L
                                    || rowMediaId.toString() != initialRecord.mediaId
                                    || generation == null
                                    || generation <= 0L
                                    || generation != initialRecord.generation
                                    || dateAdded <= 0L
                                ) {
                                    MediaStoreCandidateRowResult.Invalid
                                } else {
                                    MediaStoreCandidateRowResult.Ready(
                                        MediaStoreCandidateRecord(
                                            mediaId = rowMediaId.toString(),
                                            generation = generation,
                                            dateAddedEpochSec = dateAdded,
                                            dateModifiedEpochSec =
                                                cursor.getLongOrZero(dateModifiedIndex),
                                            metadata = MediaStoreImageMetadata(
                                                uri = itemUri.toString(),
                                                relativePath =
                                                    cursor.getStringOrNull(relativePathIndex),
                                                mimeType = cursor.getStringOrNull(mimeTypeIndex),
                                                width = cursor.getIntOrZero(widthIndex),
                                                height = cursor.getIntOrZero(heightIndex),
                                                observedAtEpochMs =
                                                    initialRecord.metadata.observedAtEpochMs,
                                            ),
                                        ),
                                    )
                                }
                            }
                        }
                    },
                    moveToNext = {
                        cursor.moveToNext()
                    },
                )
                when (cursorResult) {
                    GateKSingleRowCursorResult.NotFound ->
                        MediaStoreCandidateRowResult.NotFound

                    GateKSingleRowCursorResult.MultipleRows ->
                        MediaStoreCandidateRowResult.Invalid

                    is GateKSingleRowCursorResult.Ready ->
                        cursorResult.value
                }
            }
            val afterVersionResult = GateKCandidateReadinessPolicy.classifyExpectedMediaStoreVersion(
                expectedVersion = expectedMediaStoreVersion,
                observedVersion = readMediaStoreVersion(),
            )
            if (afterVersionResult != null) {
                val failure = (afterVersionResult as? GateKCandidateReadinessProbeResult.Failed)
                    ?.failure ?: GateKCandidateReadinessFailure.OBSERVER_ERROR
                return MediaStoreCandidateQueryResult.Failed(failure)
            }
            when (record) {
                MediaStoreCandidateRowResult.NotFound ->
                    MediaStoreCandidateQueryResult.Retryable(
                        GateKCandidateReadinessFailure.CONTENT_UNAVAILABLE,
                    )

                MediaStoreCandidateRowResult.Invalid ->
                    MediaStoreCandidateQueryResult.Failed(
                        GateKCandidateReadinessFailure.METADATA_REJECTED,
                    )

                is MediaStoreCandidateRowResult.Ready ->
                    MediaStoreCandidateQueryResult.Ready(record.record)
            }
        } catch (_: SecurityException) {
            MediaStoreCandidateQueryResult.Failed(
                GateKCandidateReadinessFailure.GRANT_UNAVAILABLE,
            )
        } catch (_: RuntimeException) {
            MediaStoreCandidateQueryResult.Failed(
                GateKCandidateReadinessFailure.QUERY_FAILED,
            )
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

    private sealed interface TransientContentResult {
        data class Ready(
            val bytes: ByteArray,
            val lease: GateKActiveReadLease,
        ) : TransientContentResult

        data object RetryableUnavailable : TransientContentResult

        data object Cancelled : TransientContentResult

        data class Failed(val failure: GateKCandidateReadinessFailure) : TransientContentResult
    }

    private fun openTransientContent(
        sessionId: String,
        attemptId: String,
        uri: Uri,
    ): TransientContentResult {
        val cancellationSignal = CancellationSignal()
        val resourceLock = Any()
        var descriptor: AssetFileDescriptor? = null
        var input: InputStream? = null
        var lease: GateKActiveReadLease? = null
        var handedOff = false

        fun closePublishedResources() {
            val resources = synchronized(resourceLock) {
                val currentInput = input
                val currentDescriptor = descriptor
                input = null
                descriptor = null
                currentInput to currentDescriptor
            }
            try {
                resources.first?.close()
            } catch (_: java.io.IOException) {
                // The read has already been cancelled or completed; close
                // errors must not become a public query/read failure.
            }
            try {
                resources.second?.close()
            } catch (_: java.io.IOException) {
                // See the input stream close above.
            }
        }

        return try {
            lease = activeReadLifecycle.beginRead(
                sessionId = sessionId,
                attemptId = attemptId,
                closeAction = {
                    try {
                        cancellationSignal.cancel()
                    } catch (_: RuntimeException) {
                        // The lifecycle cancellation flag is authoritative;
                        // a provider signal failure cannot revive the read.
                    }
                    closePublishedResources()
                },
            ) ?: return TransientContentResult.Cancelled
            if (lease?.isCancelled == true) {
                return TransientContentResult.Cancelled
            }

            val openedDescriptor = contentResolver.openAssetFileDescriptor(
                uri,
                "r",
                cancellationSignal,
            ) ?: return TransientContentResult.RetryableUnavailable
            synchronized(resourceLock) {
                descriptor = openedDescriptor
            }
            if (lease?.isCancelled == true) {
                return TransientContentResult.Cancelled
            }

            val openedInput = openedDescriptor.createInputStream()
            val published = synchronized(resourceLock) {
                if (lease?.isCancelled == true) {
                    false
                } else {
                    input = openedInput
                    true
                }
            }
            if (!published) {
                try {
                    openedInput.close()
                } catch (_: java.io.IOException) {
                    // Cancellation owns the result and close semantics.
                }
                return TransientContentResult.Cancelled
            }

            val bytes = openedInput.readBounded()
                ?: return TransientContentResult.RetryableUnavailable
            if (lease?.isCancelled == true) {
                return TransientContentResult.Cancelled
            }
            handedOff = true
            TransientContentResult.Ready(bytes, lease!!)
        } catch (_: SecurityException) {
            if (lease?.isCancelled == true) {
                TransientContentResult.Cancelled
            } else {
                TransientContentResult.Failed(
                    GateKCandidateReadinessFailure.GRANT_UNAVAILABLE,
                )
            }
        } catch (_: java.io.IOException) {
            if (lease?.isCancelled == true) {
                TransientContentResult.Cancelled
            } else {
                TransientContentResult.RetryableUnavailable
            }
        } catch (_: RuntimeException) {
            if (lease?.isCancelled == true) {
                TransientContentResult.Cancelled
            } else {
                TransientContentResult.Failed(
                    GateKCandidateReadinessFailure.QUERY_FAILED,
                )
            }
        } finally {
            if (!handedOff) {
                lease?.let { activeReadLifecycle.releaseRead(it) }
                if (lease == null) {
                    try {
                        cancellationSignal.cancel()
                    } catch (_: RuntimeException) {
                        // No lease was published; cleanup remains best effort.
                    }
                }
            }
            // A provider may return a descriptor just after cancellation has
            // already closed the lease. Re-check the holder unconditionally
            // so late-published resources cannot leak; on Ready this closes
            // the stream after the bounded read while the lease remains the
            // cancellation gate for the downstream handoff.
            closePublishedResources()
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
