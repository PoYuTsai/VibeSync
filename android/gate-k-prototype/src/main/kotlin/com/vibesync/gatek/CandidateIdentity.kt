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
        // Keep the compatibility path fail-closed before touching content:
        // rejected session/content candidates must never be hashed.
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
        return observePrepared(
            window = window,
            candidate = candidate,
            identity = CandidateIdentity(sha256(candidate.content)),
        )
    }

    /**
     * Computes the identity without touching session or dedupe state. The
     * digest is chunked so a lifecycle cancellation can stop preparation
     * between chunks before any identity is committed.
     */
    internal fun prepareIdentity(
        content: ByteArray,
        shouldContinue: () -> Boolean,
    ): CandidateIdentity? {
        if (content.isEmpty() || !shouldContinue()) return null
        val digest = MessageDigest.getInstance("SHA-256")
        val chunkSize = 64 * 1024
        var offset = 0
        while (offset < content.size) {
            if (!shouldContinue()) return null
            val length = minOf(chunkSize, content.size - offset)
            digest.update(content, offset, length)
            offset += length
        }
        if (!shouldContinue()) return null
        return CandidateIdentity(formatDigest(digest.digest()))
    }

    /** Commits a previously prepared identity while the caller owns a gate. */
    internal fun observePrepared(
        window: ImeSessionWindow,
        candidate: ScreenshotCandidate,
        identity: CandidateIdentity,
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
            activeSessionId = window.sessionId
            activeFloorEpochMs = window.floorEpochMs
            seenHashes.clear()
        }

        return if (seenHashes.add(identity.sha256)) {
            CandidateIdentityDecision.FirstSeen(identity)
        } else {
            CandidateIdentityDecision.Duplicate(identity)
        }
    }

    /** Clears identities as soon as a visible IME session ends. */
    fun clear() {
        activeSessionId = null
        activeFloorEpochMs = null
        seenHashes.clear()
    }

    private fun sha256(content: ByteArray): String {
        return formatDigest(MessageDigest.getInstance("SHA-256").digest(content))
    }

    private fun formatDigest(digest: ByteArray): String {
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
