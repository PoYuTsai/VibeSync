package com.vibesync.gatek

import java.io.IOException
import java.io.InputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GateKActiveReadLifecycleTest {
    @Test
    fun `session hide closes a blocking read before it can become ready`() {
        assertCancellationStopsRead { lifecycle, sessionId, _ ->
            lifecycle.onSessionHidden(sessionId)
        }
    }

    @Test
    fun `attempt deadline closes a blocking read before it can become ready`() {
        assertCancellationStopsRead { lifecycle, sessionId, attemptId ->
            lifecycle.onAttemptDeadline(sessionId, attemptId)
        }
    }

    @Test
    fun `service destroy closes a blocking read before it can become ready`() {
        assertCancellationStopsRead { lifecycle, _, _ ->
            lifecycle.onServiceDestroyed()
        }
    }

    @Test
    fun `session hide rejects a late stream registration`() {
        val lifecycle = GateKActiveReadLifecycle()
        lifecycle.onSessionHidden("session-1")
        val closeCount = AtomicInteger()

        val lease = lifecycle.beginRead("session-1", "attempt-1") {
            closeCount.incrementAndGet()
        }

        assertNull(lease)
        assertEquals(1, closeCount.get())
    }

    @Test
    fun `deadline rejects a late stream registration`() {
        val lifecycle = GateKActiveReadLifecycle()
        lifecycle.onAttemptDeadline("session-1", "attempt-1")
        val closeCount = AtomicInteger()

        val lease = lifecycle.beginRead("session-1", "attempt-1") {
            closeCount.incrementAndGet()
        }

        assertNull(lease)
        assertEquals(1, closeCount.get())
    }

    @Test
    fun `destroy rejects a late stream registration`() {
        val lifecycle = GateKActiveReadLifecycle()
        lifecycle.onServiceDestroyed()
        val closeCount = AtomicInteger()

        val lease = lifecycle.beginRead("session-1", "attempt-1") {
            closeCount.incrementAndGet()
        }

        assertNull(lease)
        assertEquals(1, closeCount.get())
    }

    @Test
    fun `cancellation does not wait for processing and discards a racing result`() {
        val lifecycle = GateKActiveReadLifecycle()
        val lease = lifecycle.beginRead("session-1", "attempt-1") {}
        assertNotNull(lease)
        val processingStarted = CountDownLatch(1)
        val allowProcessingToReturn = CountDownLatch(1)
        val result = AtomicReference<String?>(null)
        val worker = Thread {
            result.set(
                lease!!.runIfNotCancelled {
                    processingStarted.countDown()
                    allowProcessingToReturn.await(5, TimeUnit.SECONDS)
                    "ready"
                },
            )
        }
        worker.start()
        assertTrue(processingStarted.await(1, TimeUnit.SECONDS))

        val cancelStartedAt = System.nanoTime()
        lifecycle.onAttemptDeadline("session-1", "attempt-1")
        val cancelDurationMs = TimeUnit.NANOSECONDS.toMillis(
            System.nanoTime() - cancelStartedAt,
        )
        assertTrue("cancellation waited for processing", cancelDurationMs < 500L)

        allowProcessingToReturn.countDown()
        worker.join(1_000L)
        assertFalse(worker.isAlive)
        assertNull(result.get())
    }

    @Test
    fun `old attempt cleanup cannot close a replacement read`() {
        val lifecycle = GateKActiveReadLifecycle()
        val oldCloseCount = AtomicInteger()
        val newCloseCount = AtomicInteger()
        val old = lifecycle.beginRead("session-1", "attempt-old") {
            oldCloseCount.incrementAndGet()
        }
        assertNotNull(old)
        val replacement = lifecycle.beginRead("session-1", "attempt-new") {
            newCloseCount.incrementAndGet()
        }
        assertNotNull(replacement)

        lifecycle.onAttemptDeadline("session-1", "attempt-old")
        assertEquals(1, oldCloseCount.get())
        assertEquals(0, newCloseCount.get())
        assertFalse(replacement!!.isCancelled)

        lifecycle.releaseRead(old!!)
        assertFalse(replacement.isCancelled)
        lifecycle.onAttemptDeadline("session-1", "attempt-new")
        lifecycle.onAttemptDeadline("session-1", "attempt-new")
        assertEquals(1, newCloseCount.get())
    }

    private fun assertCancellationStopsRead(
        cancel: (GateKActiveReadLifecycle, String, String) -> Unit,
    ) {
        val lifecycle = GateKActiveReadLifecycle()
        val sessionId = "session-1"
        val attemptId = "attempt-1"
        val input = BlockingInputStream()
        val downstreamSuccesses = AtomicInteger()
        val outcome = AtomicReference<ReadOutcome>()
        val readStarted = CountDownLatch(1)
        val worker = Thread {
            val lease = lifecycle.beginRead(sessionId, attemptId, input::close)
            assertNotNull(lease)
            readStarted.countDown()
            try {
                input.read()
                val processed = lease!!.runIfNotCancelled {
                    downstreamSuccesses.incrementAndGet()
                    ReadOutcome.READY
                }
                outcome.set(processed ?: ReadOutcome.CANCELLED)
            } catch (_: IOException) {
                outcome.set(
                    if (lease!!.isCancelled) ReadOutcome.CANCELLED else ReadOutcome.READ_FAILED,
                )
            } finally {
                lifecycle.releaseRead(lease!!)
            }
        }
        worker.start()
        assertTrue(readStarted.await(1, TimeUnit.SECONDS))
        assertTrue(input.awaitReadBlocked(1, TimeUnit.SECONDS))

        cancel(lifecycle, sessionId, attemptId)

        assertTrue(input.awaitClosed(1, TimeUnit.SECONDS))
        worker.join(1_000L)
        assertFalse("blocking read did not stop", worker.isAlive)
        assertEquals(ReadOutcome.CANCELLED, outcome.get())
        assertEquals(0, downstreamSuccesses.get())
    }

    private enum class ReadOutcome {
        READY,
        CANCELLED,
        READ_FAILED,
    }

    private class BlockingInputStream : InputStream() {
        private val readBlocked = CountDownLatch(1)
        private val closed = CountDownLatch(1)

        override fun read(): Int {
            readBlocked.countDown()
            if (closed.await(5, TimeUnit.SECONDS)) {
                throw IOException("stream closed")
            }
            return -1
        }

        override fun close() {
            closed.countDown()
        }

        fun awaitReadBlocked(timeout: Long, unit: TimeUnit): Boolean =
            readBlocked.await(timeout, unit)

        fun awaitClosed(timeout: Long, unit: TimeUnit): Boolean =
            closed.await(timeout, unit)
    }
}
