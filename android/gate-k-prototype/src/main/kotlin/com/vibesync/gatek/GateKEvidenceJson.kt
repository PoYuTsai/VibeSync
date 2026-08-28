package com.vibesync.gatek

/** Stable JSON writer for evidence packets; it accepts no caller-provided summary. */
object GateKEvidenceJson {
    fun encode(
        records: List<GateKTrialRecord>,
        thresholds: GateKThresholds = GateKThresholds(),
    ): String = encode(GateKEvidenceAggregator(thresholds).build(records))

    fun encode(packet: GateKEvidencePacket): String {
        // Rebuild from raw records so a caller cannot forge the derived
        // summary by mutating a packet copy before serialization.
        val verifiedPacket = GateKEvidenceAggregator(packet.thresholds).build(packet.trialRecords)
        val records = packet.trialRecords.sortedWith(
            compareBy<GateKTrialRecord>(
                { it.trialId },
                { it.deviceClass.name },
                { it.apiLevel },
                { it.deviceModel },
                { it.success },
                { it.latencyMs },
                { it.sessionOutcome.name },
                { it.dedupeOutcome.name },
                { it.attemptId },
                { it.sessionId },
                { it.triggerElapsedRealtimeMs },
                { it.detectedElapsedRealtimeMs ?: Long.MIN_VALUE },
                { it.deviceDescriptor },
                { it.failureReason.name },
                { it.origin.name },
            ),
        )
        return buildString {
            append("{\"schemaVersion\":1,\"trialRecords\":[")
            records.joinTo(this, separator = ",") { record -> recordJson(record) }
            append("],\"summary\":")
            append(summaryJson(verifiedPacket.summary))
            append('}')
        }
    }

    private fun recordJson(record: GateKTrialRecord): String = buildString {
        append('{')
        append("\"trialId\":").append(quote(record.trialId))
        append(",\"deviceClass\":").append(quote(record.deviceClass.name))
        append(",\"apiLevel\":").append(record.apiLevel)
        append(",\"deviceModel\":").append(quote(record.deviceModel))
        append(",\"reportedSuccess\":").append(record.success)
        append(",\"latencyMs\":").append(record.latencyMs)
        append(",\"sessionOutcome\":").append(quote(record.sessionOutcome.name))
        append(",\"dedupeOutcome\":").append(quote(record.dedupeOutcome.name))
        append(",\"attemptId\":").append(quote(record.attemptId))
        append(",\"sessionId\":").append(quote(record.sessionId))
        append(",\"triggerElapsedRealtimeMs\":").append(record.triggerElapsedRealtimeMs)
        append(",\"detectedElapsedRealtimeMs\":")
            .append(record.detectedElapsedRealtimeMs?.toString() ?: "null")
        append(",\"deviceDescriptor\":").append(quote(record.deviceDescriptor))
        append(",\"failureReason\":").append(quote(record.failureReason.name))
        append(",\"origin\":").append(quote(record.origin.name))
        append('}')
    }

    private fun summaryJson(summary: GateKEvidenceSummary): String = buildString {
        append('{')
        append("\"totalTrials\":").append(summary.totalTrials)
        append(",\"successfulTrials\":").append(summary.successfulTrials)
        append(",\"failedTrials\":").append(summary.failedTrials)
        append(",\"successRate\":").append(summary.successRate)
        append(",\"p50LatencyMs\":").append(summary.p50LatencyMs?.toString() ?: "null")
        append(",\"p95LatencyMs\":").append(summary.p95LatencyMs?.toString() ?: "null")
        append(",\"minimumTrialsMet\":").append(summary.minimumTrialsMet)
        append(",\"successRateMet\":").append(summary.successRateMet)
        append(",\"latencyMet\":").append(summary.latencyMet)
        append(",\"sessionContractMet\":").append(summary.sessionContractMet)
        append(",\"dedupeContractMet\":").append(summary.dedupeContractMet)
        append(",\"runtimeOriginMet\":").append(summary.runtimeOriginMet)
        append(",\"perEmulatorApiThresholdsMet\":")
            .append(summary.perEmulatorApiThresholdsMet)
        append(",\"dataIntegrityMet\":").append(summary.dataIntegrityMet)
        append(",\"invalidRecordCount\":").append(summary.invalidRecordCount)
        append(",\"invalidTrialIds\":")
        append(summary.invalidTrialIds.joinToString(prefix = "[", postfix = "]") { quote(it) })
        append(",\"invalidAttemptIds\":")
        append(summary.invalidAttemptIds.joinToString(prefix = "[", postfix = "]") { quote(it) })
        append(",\"inconsistentSuccessTrialIds\":")
        append(summary.inconsistentSuccessTrialIds.joinToString(prefix = "[", postfix = "]") { quote(it) })
        append(",\"emulatorApiSummaries\":{")
        summary.emulatorApiSummaries.toSortedMap().entries.joinTo(this, separator = ",") { (api, group) ->
            "${quote(api.toString())}:${groupJson(group)}"
        }
        append('}')
        append(",\"emulatorCandidate\":").append(summary.emulatorCandidate)
        append(",\"decision\":").append(quote(summary.decision.name))
        append('}')
    }

    private fun groupJson(group: GateKGroupSummary): String = buildString {
        append('{')
        append("\"totalTrials\":").append(group.totalTrials)
        append(",\"successfulTrials\":").append(group.successfulTrials)
        append(",\"failedTrials\":").append(group.failedTrials)
        append(",\"successRate\":").append(group.successRate)
        append(",\"p50LatencyMs\":").append(group.p50LatencyMs?.toString() ?: "null")
        append(",\"p95LatencyMs\":").append(group.p95LatencyMs?.toString() ?: "null")
        append(",\"successRateMet\":").append(group.successRateMet)
        append(",\"latencyMet\":").append(group.latencyMet)
        append('}')
    }

    private fun quote(value: String): String = buildString(value.length + 2) {
        append('"')
        value.forEach { character ->
            when (character) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\b' -> append("\\b")
                '\u000C' -> append("\\f")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                in '\u0000'..'\u001F' -> {
                    append("\\u")
                    append(character.code.toString(16).padStart(4, '0'))
                }

                else -> append(character)
            }
        }
        append('"')
    }
}
