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
        val trial = GateKTrialRecord(
            trialId = "trial-${nextTrialNumber++}",
            deviceClass = deviceClass,
            apiLevel = apiLevel,
            deviceModel = deviceModel,
            success = success,
            latencyMs = latencyMs,
            sessionOutcome = sessionOutcome,
            dedupeOutcome = dedupeOutcome,
            failureReason = failureReason,
        )
        trialRecords += trial
        return trial
    }

    @Synchronized
    fun evidencePacket(): GateKEvidencePacket =
        GateKEvidenceAggregator(thresholds).build(trialRecords)

    fun evidenceJson(): String = GateKEvidenceJson.encode(evidencePacket())
}
