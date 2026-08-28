package com.vibesync.gatek

enum class GateKDeviceClass {
    EMULATOR,
    PHYSICAL_STOCK,
    PHYSICAL_SAMSUNG,
    UNCLASSIFIED,
}

enum class GateKSessionOutcome {
    ACCEPTED,
    IGNORED,
    REJECTED,
    NOT_EVALUATED,
}

enum class GateKDedupeOutcome {
    FIRST_SEEN,
    DUPLICATE_SUPPRESSED,
    NOT_EVALUATED,
}

enum class GateKTrialOrigin {
    RUNTIME,
    SYNTHETIC,
}

data class GateKTrialRecord(
    val trialId: String,
    val deviceClass: GateKDeviceClass,
    val apiLevel: Int,
    val deviceModel: String,
    val success: Boolean,
    val latencyMs: Long,
    val sessionOutcome: GateKSessionOutcome,
    val dedupeOutcome: GateKDedupeOutcome,
    val attemptId: String = trialId,
    val sessionId: String = "session-$trialId",
    val triggerElapsedRealtimeMs: Long = 0L,
    val detectedElapsedRealtimeMs: Long? = latencyMs,
    val deviceDescriptor: String = deviceModel,
    val failureReason: GateKFailureReason = GateKFailureReason.NONE,
    val origin: GateKTrialOrigin = GateKTrialOrigin.SYNTHETIC,
)

data class GateKThresholds(
    val minTrialsPerEmulatorApi: Int = 40,
    val successRateFloor: Double = 0.95,
    val maxP95LatencyMs: Long = 3_000L,
)

enum class GateKDecision {
    EMULATOR_CANDIDATE,
    INCONCLUSIVE,
}

data class GateKGroupSummary(
    val totalTrials: Int,
    val successfulTrials: Int,
    val failedTrials: Int,
    val successRate: Double,
    val p50LatencyMs: Long?,
    val p95LatencyMs: Long?,
    val successRateMet: Boolean,
    val latencyMet: Boolean,
)

data class GateKEvidenceSummary(
    val totalTrials: Int,
    val successfulTrials: Int,
    val failedTrials: Int,
    val successRate: Double,
    val p50LatencyMs: Long?,
    val p95LatencyMs: Long?,
    val emulatorApiTrialCounts: Map<Int, Int>,
    val minimumTrialsMet: Boolean,
    val successRateMet: Boolean,
    val latencyMet: Boolean,
    val sessionContractMet: Boolean,
    val dedupeContractMet: Boolean,
    val runtimeOriginMet: Boolean,
    val perEmulatorApiThresholdsMet: Boolean,
    val dataIntegrityMet: Boolean,
    val invalidRecordCount: Int,
    val invalidTrialIds: List<String>,
    val invalidAttemptIds: List<String>,
    val inconsistentSuccessTrialIds: List<String>,
    val emulatorApiSummaries: Map<Int, GateKGroupSummary>,
    val emulatorCandidate: Boolean,
    val decision: GateKDecision,
)

data class GateKEvidencePacket(
    val trialRecords: List<GateKTrialRecord>,
    val summary: GateKEvidenceSummary,
    val thresholds: GateKThresholds = GateKThresholds(),
)

/**
 * Computes evidence only from immutable trial records. It deliberately emits
 * an emulator-candidate decision, never a full Gate K pass decision: physical
 * device and policy evidence remain hard prerequisites outside this prototype.
 */
class GateKEvidenceAggregator(
    private val thresholds: GateKThresholds = GateKThresholds(),
) {
    private val requiredEmulatorApis = setOf(34, 35, 36)

    init {
        require(thresholds.minTrialsPerEmulatorApi > 0) {
            "minimum trial threshold must be positive"
        }
        require(thresholds.successRateFloor in 0.0..1.0) {
            "success rate threshold must be between 0 and 1"
        }
        require(thresholds.maxP95LatencyMs >= 0L) {
            "latency threshold must not be negative"
        }
    }

    fun build(records: List<GateKTrialRecord>): GateKEvidencePacket {
        val immutableRecords = records.toList()
        val totalTrials = immutableRecords.size
        val duplicateTrialIds = immutableRecords
            .filter { it.trialId.isNotBlank() }
            .groupingBy { it.trialId }
            .eachCount()
            .filterValues { it > 1 }
            .keys
        val duplicateAttemptIds = immutableRecords
            .filter { it.attemptId.isNotBlank() }
            .groupingBy { it.attemptId }
            .eachCount()
            .filterValues { it > 1 }
            .keys
        val invalidRecords = immutableRecords.filter { record ->
            record.trialId.isBlank()
                || record.attemptId.isBlank()
                || record.sessionId.isBlank()
                || record.deviceModel.isBlank()
                || record.deviceDescriptor.isBlank()
                || record.apiLevel <= 0
                || !timingIsConsistent(record)
                || record.trialId in duplicateTrialIds
                || record.attemptId in duplicateAttemptIds
        }
        val invalidTrialIds = invalidRecords
            .map { it.trialId.ifBlank { "<blank>" } }
            .distinct()
            .sorted()
        val invalidAttemptIds = invalidRecords
            .map { it.attemptId.ifBlank { "<blank>" } }
            .distinct()
            .sorted()
        val effectiveSuccess = immutableRecords.map { record ->
            isVerifiableSuccess(record)
        }
        val successfulTrials = effectiveSuccess.count { it }
        val sortedLatencies = immutableRecords
            .filter { it.latencyMs >= 0L }
            .map { it.latencyMs }
            .sorted()
        val successRate = if (totalTrials == 0) {
            0.0
        } else {
            successfulTrials.toDouble() / totalTrials.toDouble()
        }
        val emulatorApiTrialCounts = immutableRecords
            .filter { it.deviceClass == GateKDeviceClass.EMULATOR }
            .groupingBy { it.apiLevel }
            .eachCount()
            .toSortedMap()
        val minimumTrialsMet = requiredEmulatorApis.all { apiLevel ->
            (emulatorApiTrialCounts[apiLevel] ?: 0) >= thresholds.minTrialsPerEmulatorApi
        }
        val successRateMet = totalTrials > 0 && successRate >= thresholds.successRateFloor
        val p95LatencyMs = percentileNearestRank(sortedLatencies, 0.95)
        val latencyMet = p95LatencyMs != null && p95LatencyMs <= thresholds.maxP95LatencyMs
        val sessionContractMet = immutableRecords.isNotEmpty()
            && immutableRecords.all { it.sessionOutcome != GateKSessionOutcome.NOT_EVALUATED }
        val dedupeContractMet = immutableRecords.isNotEmpty()
            && immutableRecords.all { it.dedupeOutcome != GateKDedupeOutcome.NOT_EVALUATED }
        val runtimeOriginMet = immutableRecords.isNotEmpty()
            && immutableRecords.all { it.origin == GateKTrialOrigin.RUNTIME }
        val emulatorApiSummaries = requiredEmulatorApis
            .associateWith { apiLevel -> summarizeGroup(immutableRecords.filter { record ->
                record.deviceClass == GateKDeviceClass.EMULATOR && record.apiLevel == apiLevel
            }) }
            .toSortedMap()
        val perEmulatorApiThresholdsMet = requiredEmulatorApis.all { apiLevel ->
            val group = emulatorApiSummaries.getValue(apiLevel)
            group.totalTrials >= thresholds.minTrialsPerEmulatorApi
                && group.successRateMet
                && group.latencyMet
        }
        val inconsistentSuccessTrialIds = immutableRecords
            .filter { record -> record.success != outcomeIndicatesSuccess(record) }
            .map { it.trialId.ifBlank { "<blank>" } }
            .sorted()
        val dataIntegrityMet = invalidRecords.isEmpty() && inconsistentSuccessTrialIds.isEmpty()
        val allEmulator = immutableRecords.isNotEmpty()
            && immutableRecords.all { it.deviceClass == GateKDeviceClass.EMULATOR }
        val emulatorCandidate = allEmulator
            && minimumTrialsMet
            && successRateMet
            && latencyMet
            && sessionContractMet
            && dedupeContractMet
            && runtimeOriginMet
            && perEmulatorApiThresholdsMet
            && dataIntegrityMet

        val summary = GateKEvidenceSummary(
            totalTrials = totalTrials,
            successfulTrials = successfulTrials,
            failedTrials = totalTrials - successfulTrials,
            successRate = successRate,
            p50LatencyMs = percentileNearestRank(sortedLatencies, 0.50),
            p95LatencyMs = p95LatencyMs,
            emulatorApiTrialCounts = emulatorApiTrialCounts,
            minimumTrialsMet = minimumTrialsMet,
            successRateMet = successRateMet,
            latencyMet = latencyMet,
            sessionContractMet = sessionContractMet,
            dedupeContractMet = dedupeContractMet,
            runtimeOriginMet = runtimeOriginMet,
            perEmulatorApiThresholdsMet = perEmulatorApiThresholdsMet,
            dataIntegrityMet = dataIntegrityMet,
            invalidRecordCount = invalidRecords.size,
            invalidTrialIds = invalidTrialIds,
            invalidAttemptIds = invalidAttemptIds,
            inconsistentSuccessTrialIds = inconsistentSuccessTrialIds,
            emulatorApiSummaries = emulatorApiSummaries,
            emulatorCandidate = emulatorCandidate,
            decision = if (emulatorCandidate) {
                GateKDecision.EMULATOR_CANDIDATE
            } else {
                GateKDecision.INCONCLUSIVE
            },
        )
        return GateKEvidencePacket(
            trialRecords = immutableRecords,
            summary = summary,
            thresholds = thresholds,
        )
    }

    private fun isVerifiableSuccess(record: GateKTrialRecord): Boolean =
        record.success
            && record.attemptId.isNotBlank()
            && record.sessionId.isNotBlank()
            && timingIsConsistent(record)
            && outcomeIndicatesSuccess(record)

    private fun timingIsConsistent(record: GateKTrialRecord): Boolean {
        val detectedAt = record.detectedElapsedRealtimeMs ?: return false
        return record.triggerElapsedRealtimeMs >= 0L
            && record.latencyMs >= 0L
            && detectedAt >= record.triggerElapsedRealtimeMs
            && detectedAt - record.triggerElapsedRealtimeMs == record.latencyMs
    }

    private fun outcomeIndicatesSuccess(record: GateKTrialRecord): Boolean =
        record.failureReason == GateKFailureReason.NONE
            && record.sessionOutcome == GateKSessionOutcome.ACCEPTED
            && record.dedupeOutcome == GateKDedupeOutcome.FIRST_SEEN
            && record.latencyMs in 0L..thresholds.maxP95LatencyMs

    private fun summarizeGroup(records: List<GateKTrialRecord>): GateKGroupSummary {
        val validLatencies = records.filter { it.latencyMs >= 0L }.map { it.latencyMs }.sorted()
        val successes = records.count { isVerifiableSuccess(it) }
        val total = records.size
        val rate = if (total == 0) 0.0 else successes.toDouble() / total.toDouble()
        val p95 = percentileNearestRank(validLatencies, 0.95)
        return GateKGroupSummary(
            totalTrials = total,
            successfulTrials = successes,
            failedTrials = total - successes,
            successRate = rate,
            p50LatencyMs = percentileNearestRank(validLatencies, 0.50),
            p95LatencyMs = p95,
            successRateMet = total > 0 && rate >= thresholds.successRateFloor,
            latencyMet = p95 != null && p95 <= thresholds.maxP95LatencyMs,
        )
    }

    private fun percentileNearestRank(sortedValues: List<Long>, percentile: Double): Long? {
        if (sortedValues.isEmpty()) return null
        val rank = kotlin.math.ceil(sortedValues.size * percentile).toInt().coerceAtLeast(1)
        return sortedValues[rank - 1]
    }
}
