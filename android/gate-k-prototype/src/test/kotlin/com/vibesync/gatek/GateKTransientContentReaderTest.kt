package com.vibesync.gatek

import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GateKTransientContentReaderTest {
    @Test
    fun `successful read returns a snapshot and clears scratch buffers`() {
        val source = byteArrayOf(1, 2, 3, 4, 5)
        val readBuffer = ByteArray(4) { 0x7f }
        val output = GateKZeroizingByteArrayOutputStream(
            maxBytes = 16,
            initialCapacity = 2,
        )

        val result = GateKTransientContentReader.readBounded(
            input = ByteArrayInputStream(source),
            maxBytes = 16,
            readBuffer = readBuffer,
            output = output,
        )

        assertArrayEquals(source, requireNotNull(result))
        assertTrue(readBuffer.all { it == 0.toByte() })
        assertTrue(output.isZeroized())
    }

    @Test
    fun `oversized read returns null and clears scratch buffers`() {
        val readBuffer = ByteArray(3) { 0x7f }
        val output = GateKZeroizingByteArrayOutputStream(
            maxBytes = 4,
            initialCapacity = 2,
        )

        val result = GateKTransientContentReader.readBounded(
            input = ByteArrayInputStream(ByteArray(5) { 0x2a }),
            maxBytes = 4,
            readBuffer = readBuffer,
            output = output,
        )

        assertNull(result)
        assertTrue(readBuffer.all { it == 0.toByte() })
        assertTrue(output.isZeroized())
    }

    @Test
    fun `io exception returns through caller and clears scratch buffers`() {
        val readBuffer = ByteArray(4) { 0x7f }
        val output = GateKZeroizingByteArrayOutputStream(
            maxBytes = 16,
            initialCapacity = 2,
        )

        try {
            GateKTransientContentReader.readBounded(
                input = FailingInputStream(IOException("read failed")),
                maxBytes = 16,
                readBuffer = readBuffer,
                output = output,
            )
            throw AssertionError("expected IOException")
        } catch (_: IOException) {
            // The service maps this as a retryable read failure unless the
            // active lease has already cancelled it.
        }

        assertTrue(readBuffer.all { it == 0.toByte() })
        assertTrue(output.isZeroized())
    }

    @Test
    fun `runtime exception clears scratch buffers too`() {
        val readBuffer = ByteArray(4) { 0x7f }
        val output = GateKZeroizingByteArrayOutputStream(
            maxBytes = 16,
            initialCapacity = 2,
        )

        try {
            GateKTransientContentReader.readBounded(
                input = FailingInputStream(IllegalStateException("read failed")),
                maxBytes = 16,
                readBuffer = readBuffer,
                output = output,
            )
            throw AssertionError("expected IllegalStateException")
        } catch (_: IllegalStateException) {
            // All scratch memory is cleared by the reader's finally block.
        }

        assertTrue(readBuffer.all { it == 0.toByte() })
        assertTrue(output.isZeroized())
    }

    private class FailingInputStream(
        private val failure: Throwable,
    ) : InputStream() {
        override fun read(): Int = throw failure

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            buffer[offset] = 0x5a
            throw failure
        }
    }
}
