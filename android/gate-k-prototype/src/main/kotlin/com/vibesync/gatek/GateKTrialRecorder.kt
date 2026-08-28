package com.vibesync.gatek

/**
 * In-memory raw trial sink for the disposable prototype. It intentionally
 * stores metadata only; screenshot bytes and chat text never enter a trial
 * record. Device evidence remains unclassified unless the harness explicitly
 * supplies a verified device class.
 */
class GateKTrialRecorder(
    private val deviceClass: GateKDeviceClass,
    private val apiLevel: Int,
    private val deviceModel: String,
    private val thresholds: GateKThresholds = GateKThresholds(),
    private val rawDeviceDescriptor: GateKDeviceDescriptor = GateKDeviceDescriptor(
        manufacturer = "",
        brand = "",
        model = deviceModel,
        product = "",
        fingerprint = "",
        apiLevel = apiLevel,
    ),
) {
    companion object {
        const val DEFAULT_MAX_OBSERVATION_LATENCY_MS = 3_000L
    }

    private val trialRecords = mutableListOf<GateKTrialRecord>()
    private var nextTrialNumber = 1

    @get:Synchronized
    val records: List<GateKTrialRecord>
        get() = trialRecords.toList()

    @Synchronized
    fun record(
        success: Boolean,
        latencyMs: Long,
        sessionOutcome: GateKSessionOutcome,
        dedupeOutcome: GateKDedupeOutcome,
        failureReason: String? = null,
    ): GateKTrialRecord {
        val trialNumber = nextTrialNumber++
        val trial = GateKTrialRecord(
            trialId = "trial-$trialNumber",
            deviceClass = deviceClass,
            apiLevel = apiLevel,
            deviceModel = deviceModel,
            success = success,
            latencyMs = latencyMs,
            sessionOutcome = sessionOutcome,
            dedupeOutcome = dedupeOutcome,
            attemptId = "trial-$trialNumber",
            sessionId = "session-$trialNumber",
            triggerElapsedRealtimeMs = 0L,
            detectedElapsedRealtimeMs = latencyMs,
            deviceDescriptor = rawDeviceDescriptor.canonical(),
            failureReason = GateKFailureReason.fromLegacy(failureReason),
            origin = GateKTrialOrigin.SYNTHETIC,
        )
        trialRecords += trial
        return trial
    }

    /** Records a terminal produced by the runtime attempt coordinator. */
    @Synchronized
    fun recordTerminal(terminal: GateKAttemptTerminal): GateKTrialRecord {
        val trial = GateKTrialRecord(
            trialId = "trial-${nextTrialNumber++}",
            deviceClass = deviceClass,
            apiLevel = apiLevel,
            deviceModel = deviceModel,
            success = terminal.state == GateKAttemptState.SUCCEEDED,
            latencyMs = terminal.latencyMs,
            sessionOutcome = terminal.sessionOutcome,
            dedupeOutcome = terminal.dedupeOutcome,
            attemptId = terminal.attemptId.value,
            sessionId = terminal.sessionId,
            triggerElapsedRealtimeMs = terminal.triggeredAtElapsedRealtimeMs,
            detectedElapsedRealtimeMs = terminal.detectedAtElapsedRealtimeMs,
            deviceDescriptor = rawDeviceDescriptor.canonical(),
            failureReason = terminal.failureReason,
            origin = GateKTrialOrigin.RUNTIME,
        )
        trialRecords += trial
        return trial
    }

    @Synchronized
    fun evidencePacket(): GateKEvidencePacket =
        GateKEvidenceAggregator(thresholds).build(trialRecords)

    fun evidenceJson(): String = GateKEvidenceJson.encode(evidencePacket())
}
