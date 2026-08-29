package com.vibesync.gatek

import java.io.InputStream

/**
 * A bounded ByteArrayOutputStream that clears every backing array it owns.
 * Growth is kept local so the old backing array is wiped immediately after
 * its contents are copied into the replacement.
 */
internal class GateKZeroizingByteArrayOutputStream(
    private val maxBytes: Int,
    initialCapacity: Int,
) : java.io.ByteArrayOutputStream(initialCapacity) {
    init {
        require(maxBytes > 0) { "maxBytes must be positive" }
        require(initialCapacity in 1..maxBytes) {
            "initialCapacity must be within the bounded read size"
        }
    }

    internal val limitBytes: Int
        get() = maxBytes

    override fun write(source: ByteArray, offset: Int, length: Int) {
        require(offset >= 0 && length >= 0 && offset <= source.size - length) {
            "write range must fit source"
        }
        require(length <= maxBytes - count) { "bounded output exceeded" }
        ensureCapacity(count + length)
        source.copyInto(
            destination = buf,
            destinationOffset = count,
            startIndex = offset,
            endIndex = offset + length,
        )
        count += length
    }

    override fun write(oneByte: Int) {
        require(count < maxBytes) { "bounded output exceeded" }
        ensureCapacity(count + 1)
        buf[count] = oneByte.toByte()
        count += 1
    }

    fun wipe() {
        buf.fill(0)
        reset()
    }

    /** Exposes only the zeroization invariant to package-local tests. */
    internal fun isZeroized(): Boolean = size() == 0 && buf.all { it == 0.toByte() }

    private fun ensureCapacity(required: Int) {
        if (required <= buf.size) return

        val oldBuffer = buf
        val doubledCapacity = if (oldBuffer.size > maxBytes / 2) {
            maxBytes
        } else {
            oldBuffer.size * 2
        }
        val newCapacity = maxOf(required, minOf(maxBytes, doubledCapacity))
        val newBuffer = oldBuffer.copyOf(newCapacity)
        oldBuffer.fill(0)
        buf = newBuffer
    }
}

/** Reads transient content while clearing all owned scratch buffers on exit. */
internal object GateKTransientContentReader {
    fun readBounded(
        input: InputStream,
        maxBytes: Int,
        readBuffer: ByteArray,
        output: GateKZeroizingByteArrayOutputStream,
    ): ByteArray? {
        return try {
            require(readBuffer.isNotEmpty()) { "readBuffer must not be empty" }
            require(maxBytes == output.limitBytes) {
                "maxBytes must match output limit"
            }
            var total = 0
            while (true) {
                val read = input.read(readBuffer)
                if (read < 0) break
                if (read > maxBytes - total) return null
                output.write(readBuffer, 0, read)
                total += read
            }
            output.toByteArray()
        } finally {
            readBuffer.fill(0)
            output.wipe()
        }
    }
}
