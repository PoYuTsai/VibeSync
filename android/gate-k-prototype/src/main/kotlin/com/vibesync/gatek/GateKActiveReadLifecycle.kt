package com.vibesync.gatek

import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Why an active read needs its own lifecycle boundary:
 *
 * Gate K uses one serialized MediaStore worker. A blocking content stream
 * occupies that worker, so hide/deadline/destroy cannot wait for another task
 * on the same executor to cancel it. This small seam keeps the current stream
 * directly reachable from lifecycle callbacks that run outside that worker.
 */
internal class GateKActiveReadLifecycle {
    private companion object {
        const val MAX_RETAINED_CANCELLED_KEYS = 256
    }

    private val lock = Any()
    private var activeRead: GateKActiveReadLease? = null
    private var destroyed = false
    private val hiddenSessionIds = LinkedHashSet<String>()
    private val deadlineAttemptKeys = LinkedHashSet<GateKAttemptReadKey>()

    /**
     * Registers the one stream currently being read. Replacing a stale lease
     * cancels only that old lease; release uses object identity so old worker
     * cleanup cannot remove or close a newer attempt.
     */
    fun beginRead(
        sessionId: String,
        attemptId: String,
        closeAction: () -> Unit,
    ): GateKActiveReadLease? {
        require(sessionId.isNotBlank()) { "session id must not be blank" }
        require(attemptId.isNotBlank()) { "attempt id must not be blank" }

        val lease = GateKActiveReadLease(
            sessionId = sessionId,
            attemptId = attemptId,
            closeAction = closeAction,
        )
        val previous = synchronized(lock) {
            if (destroyed
                || sessionId in hiddenSessionIds
                || GateKAttemptReadKey(sessionId, attemptId) in deadlineAttemptKeys
            ) {
                return@synchronized null
            }
            val previousLease = activeRead
            activeRead = lease
            previousLease
        }
        if (destroyedOrRejected(lease)) {
            return null
        }
        previous?.cancel(GateKActiveReadCancellation.REPLACED)
        return lease
    }

    /** Cancels a read belonging to the session that is being hidden. */
    fun onSessionHidden(sessionId: String?) {
        val lease = synchronized(lock) {
            if (sessionId == null) {
                activeRead
            } else {
                rememberBounded(hiddenSessionIds, sessionId)
                activeRead?.takeIf { it.sessionId == sessionId }
            }
        }
        lease?.cancel(GateKActiveReadCancellation.SESSION_HIDDEN)
    }

    /**
     * Cancels only the exact attempt whose timeout fired. A late timeout from
     * an old attempt therefore cannot close a replacement stream.
     */
    fun onAttemptDeadline(sessionId: String, attemptId: String) {
        require(sessionId.isNotBlank()) { "session id must not be blank" }
        require(attemptId.isNotBlank()) { "attempt id must not be blank" }
        val key = GateKAttemptReadKey(sessionId, attemptId)
        val lease = synchronized(lock) {
            rememberBounded(deadlineAttemptKeys, key)
            activeRead?.takeIf { it.sessionId == sessionId && it.attemptId == attemptId }
        }
        lease?.cancel(GateKActiveReadCancellation.ATTEMPT_DEADLINE)
    }

    /** Cancels all current/future reads after the service enters destroy. */
    fun onServiceDestroyed() {
        val lease = synchronized(lock) {
            destroyed = true
            val current = activeRead
            activeRead = null
            current
        }
        lease?.cancel(GateKActiveReadCancellation.SERVICE_DESTROYED)
    }

    /** Cancels a stale stream when no active session identity is available. */
    fun cancelAllActiveRead() {
        val lease = synchronized(lock) { activeRead }
        lease?.cancel(GateKActiveReadCancellation.SESSION_HIDDEN)
    }

    /**
     * Returns the lifecycle cancellation that should stop an in-flight
     * candidate. This check remains useful after the stream has returned but
     * before its bytes are allowed into the observation pipeline.
     */
    fun cancellationFor(sessionId: String, attemptId: String): GateKActiveReadCancellation? =
        synchronized(lock) {
            when {
                destroyed -> GateKActiveReadCancellation.SERVICE_DESTROYED
                sessionId in hiddenSessionIds -> GateKActiveReadCancellation.SESSION_HIDDEN
                GateKAttemptReadKey(sessionId, attemptId) in deadlineAttemptKeys ->
                    GateKActiveReadCancellation.ATTEMPT_DEADLINE

                else -> null
            }
        }

    /** Releases a completed read without affecting any replacement lease. */
    fun releaseRead(lease: GateKActiveReadLease) {
        synchronized(lock) {
            if (activeRead === lease) {
                activeRead = null
            }
        }
        lease.close()
    }

    private fun destroyedOrRejected(lease: GateKActiveReadLease): Boolean {
        // A null previous lease is also the value produced when beginRead was
        // rejected. Distinguish it by checking the synchronized state again;
        // this avoids exposing a lease after destroy/hidden/deadline races.
        val accepted = synchronized(lock) { activeRead === lease && !destroyed }
        if (!accepted) {
            lease.cancel(GateKActiveReadCancellation.SERVICE_DESTROYED)
        }
        return !accepted
    }

    private fun <T> rememberBounded(set: LinkedHashSet<T>, value: T) {
        set += value
        while (set.size > MAX_RETAINED_CANCELLED_KEYS) {
            set.remove(set.first())
        }
    }
}

internal data class GateKAttemptReadKey(
    val sessionId: String,
    val attemptId: String,
)

internal enum class GateKActiveReadCancellation {
    SESSION_HIDDEN,
    ATTEMPT_DEADLINE,
    SERVICE_DESTROYED,
    REPLACED,
}

/** A stream lease whose cancel and close operations are independently idempotent. */
internal class GateKActiveReadLease internal constructor(
    val sessionId: String,
    val attemptId: String,
    private val closeAction: () -> Unit,
) {
    private val closed = AtomicBoolean(false)
    private val state = AtomicReference(GateKActiveReadState.ACTIVE)
    /** Serializes only the short final commit with cancellation. */
    private val commitLock = Any()
    @Volatile
    private var cancellation: GateKActiveReadCancellation? = null

    val isCancelled: Boolean
        get() = state.get() == GateKActiveReadState.CANCELLED

    val cancellationReason: GateKActiveReadCancellation?
        get() = cancellation

    fun cancel(reason: GateKActiveReadCancellation): Boolean {
        val newlyCancelled = synchronized(commitLock) {
            if (state.compareAndSet(
                    GateKActiveReadState.ACTIVE,
                    GateKActiveReadState.CANCELLED,
                ) || state.compareAndSet(
                    GateKActiveReadState.PROCESSING,
                    GateKActiveReadState.CANCELLED,
                )
            ) {
                cancellation = reason
                true
            } else {
                false
            }
        }
        close()
        return newlyCancelled
    }

    /** Closes the underlying stream once, including on ordinary completion. */
    fun close(): Boolean {
        if (!closed.compareAndSet(false, true)) return false
        try {
            closeAction()
        } catch (_: Exception) {
            // A close failure must not turn a cancelled read into a query
            // failure or allow it to reach the success path.
        }
        return true
    }

    /**
     * Atomically gates the handoff into hashing/observation against cancel.
     * If cancellation wins first, the callback is never invoked.
     */
    fun <T> runIfNotCancelled(block: () -> T): T? {
        if (!state.compareAndSet(
                GateKActiveReadState.ACTIVE,
                GateKActiveReadState.PROCESSING,
            )
        ) {
            return null
        }
        return try {
            val result = block()
            if (state.compareAndSet(
                    GateKActiveReadState.PROCESSING,
                    GateKActiveReadState.COMPLETED,
                )
            ) {
                result
            } else {
                null
            }
        } catch (error: Throwable) {
            state.compareAndSet(
                GateKActiveReadState.PROCESSING,
                GateKActiveReadState.COMPLETED,
            )
            throw error
        }
    }

    /**
     * Runs cancellable preparation outside the commit lock, then performs one
     * short linearizable commit. Cancellation can therefore stop a long hash
     * promptly, while the final mutable operation cannot race a cancellation:
     * whichever acquires [commitLock] first owns the boundary.
     */
    fun <P, T> runCancellable(
        prepare: (shouldContinue: () -> Boolean) -> P?,
        commit: (P) -> T,
    ): T? {
        if (!state.compareAndSet(
                GateKActiveReadState.ACTIVE,
                GateKActiveReadState.PROCESSING,
            )
        ) {
            return null
        }
        return try {
            val prepared = prepare { state.get() == GateKActiveReadState.PROCESSING }
                ?: return null
            synchronized(commitLock) {
                if (state.get() != GateKActiveReadState.PROCESSING) {
                    return@synchronized null
                }
                val result = commit(prepared)
                state.set(GateKActiveReadState.COMPLETED)
                result
            }
        } finally {
            // A cancelled preparation must not leave the lease in PROCESSING;
            // cancellation remains authoritative if it won the final gate.
            state.compareAndSet(
                GateKActiveReadState.PROCESSING,
                GateKActiveReadState.COMPLETED,
            )
        }
    }
}

private enum class GateKActiveReadState {
    ACTIVE,
    PROCESSING,
    CANCELLED,
    COMPLETED,
}
