package com.vibesync.gatek

import java.security.MessageDigest

data class CandidateIdentity(
    val sha256: String,
)

sealed interface CandidateIdentityDecision {
    data class FirstSeen(val identity: CandidateIdentity) : CandidateIdentityDecision

    data class Duplicate(val identity: CandidateIdentity) : CandidateIdentityDecision

    data object RejectedWrongSession : CandidateIdentityDecision

    data object RejectedEmptyContent : CandidateIdentityDecision

    data object RejectedStaleSession : CandidateIdentityDecision
}

/**
 * Retains only SHA-256 identities for the active session. Image bytes are not
 * retained after this call returns.
 */
class ScreenshotCandidateDedupe {
    private var activeSessionId: String? = null
    private var activeFloorEpochMs: Long? = null
    private val seenHashes = mutableSetOf<String>()

    fun observe(
        window: ImeSessionWindow,
        candidate: ScreenshotCandidate,
    ): CandidateIdentityDecision {
        if (candidate.sessionId != window.sessionId) {
            return CandidateIdentityDecision.RejectedWrongSession
        }
        if (candidate.content.isEmpty()) {
            return CandidateIdentityDecision.RejectedEmptyContent
        }

        val previousFloor = activeFloorEpochMs
        if (previousFloor != null && window.floorEpochMs < previousFloor) {
            return CandidateIdentityDecision.RejectedStaleSession
        }
        if (activeSessionId != window.sessionId) {
            if (previousFloor != null && window.floorEpochMs == previousFloor) {
                return CandidateIdentityDecision.RejectedStaleSession
            }
            activeSessionId = window.sessionId
            activeFloorEpochMs = window.floorEpochMs
            seenHashes.clear()
        }

        val identity = CandidateIdentity(sha256(candidate.content))
        return if (seenHashes.add(identity.sha256)) {
            CandidateIdentityDecision.FirstSeen(identity)
        } else {
            CandidateIdentityDecision.Duplicate(identity)
        }
    }

    private fun sha256(content: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(content)
        val hex = "0123456789abcdef"
        return buildString(digest.size * 2) {
            digest.forEach { byte ->
                val value = byte.toInt() and 0xff
                append(hex[value ushr 4])
                append(hex[value and 0x0f])
            }
        }
    }
}
