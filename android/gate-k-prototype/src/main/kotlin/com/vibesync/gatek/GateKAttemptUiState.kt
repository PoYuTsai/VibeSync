package com.vibesync.gatek

/** Public, session-bound readiness state for the user-facing attempt button. */
class GateKAttemptUiState {
    private var activeSessionId: String? = null
    private var observerReady = false
    private var sessionFailStopped = false

    @Synchronized
    fun onSessionShown(sessionId: String): Boolean {
        if (sessionId.isBlank()) return false
        activeSessionId = sessionId
        observerReady = false
        sessionFailStopped = false
        return true
    }

    @Synchronized
    fun onObserverReady(sessionId: String): Boolean {
        if (sessionId.isBlank() || activeSessionId != sessionId) return false
        if (sessionFailStopped) return false
        observerReady = true
        return true
    }

    @Synchronized
    fun onObserverNotReady(sessionId: String): Boolean {
        if (activeSessionId != sessionId) return false
        observerReady = false
        return true
    }

    /** Disables the attempt button for the rest of this IME session. */
    @Synchronized
    fun onAttemptFailed(sessionId: String): Boolean {
        if (activeSessionId != sessionId) return false
        observerReady = false
        sessionFailStopped = true
        return true
    }

    /**
     * Validates a delayed readiness retry against the still-live observer
     * infrastructure. A stale handler must not revive a failed session.
     */
    @Synchronized
    fun canRetryObserverReady(
        sessionId: String,
        baselineActive: Boolean,
        observerRegistered: Boolean,
    ): Boolean =
        sessionId.isNotBlank()
            && activeSessionId == sessionId
            && !observerReady
            && !sessionFailStopped
            && baselineActive
            && observerRegistered

    @Synchronized
    fun onSessionHidden(sessionId: String): Boolean {
        if (activeSessionId != sessionId) return false
        activeSessionId = null
        observerReady = false
        sessionFailStopped = false
        return true
    }

    @Synchronized
    fun isEnabled(sessionId: String): Boolean =
        sessionId.isNotBlank()
            && activeSessionId == sessionId
            && observerReady
            && !sessionFailStopped
}
