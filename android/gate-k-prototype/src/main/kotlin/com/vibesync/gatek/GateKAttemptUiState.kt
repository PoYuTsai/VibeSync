package com.vibesync.gatek

/** Public, session-bound readiness state for the user-facing attempt button. */
class GateKAttemptUiState {
    private var activeSessionId: String? = null
    private var observerReady = false

    @Synchronized
    fun onSessionShown(sessionId: String): Boolean {
        if (sessionId.isBlank()) return false
        activeSessionId = sessionId
        observerReady = false
        return true
    }

    @Synchronized
    fun onObserverReady(sessionId: String): Boolean {
        if (sessionId.isBlank() || activeSessionId != sessionId) return false
        observerReady = true
        return true
    }

    @Synchronized
    fun onObserverNotReady(sessionId: String): Boolean {
        if (activeSessionId != sessionId) return false
        observerReady = false
        return true
    }

    @Synchronized
    fun onSessionHidden(sessionId: String): Boolean {
        if (activeSessionId != sessionId) return false
        activeSessionId = null
        observerReady = false
        return true
    }

    @Synchronized
    fun isEnabled(sessionId: String): Boolean =
        sessionId.isNotBlank() && activeSessionId == sessionId && observerReady
}
