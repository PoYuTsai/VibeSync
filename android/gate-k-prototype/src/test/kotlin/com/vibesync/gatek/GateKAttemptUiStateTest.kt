package com.vibesync.gatek

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GateKAttemptUiStateTest {
    @Test
    fun `button stays disabled until the exact active session is ready`() {
        val state = GateKAttemptUiState()

        state.onSessionShown("session-1")
        assertFalse(state.isEnabled("session-1"))
        assertFalse(state.onObserverReady("other-session"))
        assertFalse(state.isEnabled("session-1"))
        assertTrue(state.onObserverReady("session-1"))
        assertTrue(state.isEnabled("session-1"))
    }

    @Test
    fun `observer failure and hidden session disable the button immediately`() {
        val state = GateKAttemptUiState()

        state.onSessionShown("session-1")
        state.onObserverReady("session-1")
        assertTrue(state.isEnabled("session-1"))
        state.onObserverNotReady("session-1")
        assertFalse(state.isEnabled("session-1"))

        state.onObserverReady("session-1")
        state.onSessionHidden("session-1")
        assertFalse(state.isEnabled("session-1"))
        assertFalse(state.onObserverReady("session-1"))
    }

    @Test
    fun `non-success terminal fail stops readiness for the rest of the session`() {
        val state = GateKAttemptUiState()

        state.onSessionShown("session-1")
        state.onObserverReady("session-1")
        assertTrue(state.isEnabled("session-1"))

        assertTrue(state.onAttemptFailed("session-1"))
        assertFalse(state.isEnabled("session-1"))
        assertFalse(state.onObserverReady("session-1"))
    }
}
