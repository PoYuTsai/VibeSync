package com.vibesync.gatek

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class GateKSingleRowCursorPolicyTest {
    @Test
    fun `single row is snapshotted before cursor advances after last`() {
        val cursor = FakeCursor(listOf("one"))

        val result = GateKSingleRowCursorPolicy.readExactlyOne(
            moveToFirst = cursor::moveToFirst,
            snapshot = cursor::snapshot,
            moveToNext = cursor::moveToNext,
        )

        assertEquals(GateKSingleRowCursorResult.Ready("one"), result)
        assertEquals(listOf("first", "snapshot", "next"), cursor.events)
        assertFalse(cursor.readAfterLast)
    }

    @Test
    fun `multiple rows are rejected after first row snapshot`() {
        val cursor = FakeCursor(listOf("one", "two"))

        val result = GateKSingleRowCursorPolicy.readExactlyOne(
            moveToFirst = cursor::moveToFirst,
            snapshot = cursor::snapshot,
            moveToNext = cursor::moveToNext,
        )

        assertEquals(GateKSingleRowCursorResult.MultipleRows, result)
        assertEquals(listOf("first", "snapshot", "next"), cursor.events)
        assertFalse(cursor.readAfterLast)
    }

    private class FakeCursor(private val rows: List<String>) {
        private var position = -1
        val events = mutableListOf<String>()
        var readAfterLast = false
            private set

        fun moveToFirst(): Boolean {
            events += "first"
            position = if (rows.isEmpty()) -1 else 0
            return rows.isNotEmpty()
        }

        fun moveToNext(): Boolean {
            events += "next"
            position += 1
            return position < rows.size
        }

        fun snapshot(): String {
            events += "snapshot"
            if (position !in rows.indices) {
                readAfterLast = true
                throw AssertionError("snapshot read after cursor moved")
            }
            return rows[position]
        }
    }
}
