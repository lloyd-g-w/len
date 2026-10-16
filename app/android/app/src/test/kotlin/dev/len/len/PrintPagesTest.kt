package dev.len.len

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PrintPagesTest {
    private val all = 0..PrintPages.ALL_END

    @Test
    fun allPagesBecomesEveryPageOfTheDocument() {
        assertEquals(listOf(0..4), PrintPages.requested(listOf(all), 5))
    }

    @Test
    fun allPagesOfAnUncountedDocumentStaysOpen() {
        assertEquals(listOf(all), PrintPages.requested(listOf(all), PrintPages.UNKNOWN))
    }

    @Test
    fun rangesAreSortedAndMerged() {
        assertEquals(
            listOf(0..3, 6..6),
            PrintPages.requested(listOf(6..6, 2..3, 0..1, 1..2), 8),
        )
    }

    @Test
    fun adjacentRangesJoin() {
        assertEquals(listOf(0..5), PrintPages.requested(listOf(0..2, 3..5), 6))
    }

    @Test
    fun pagesBeyondTheDocumentAreRefused() {
        assertNull(PrintPages.requested(listOf(0..1, 4..5), 5))
    }

    @Test
    fun nothingOrBackwardsIsRefused() {
        assertNull(PrintPages.requested(emptyList(), 3))
        assertNull(PrintPages.requested(listOf(2..1), 3))
        assertNull(PrintPages.requested(listOf(-1..0), 3))
        assertNull(PrintPages.requested(listOf(all), 0))
    }

    @Test
    fun anUncountedDocumentTakesAnyPages() {
        assertEquals(listOf(3..9), PrintPages.requested(listOf(3..9), PrintPages.UNKNOWN))
    }

    @Test
    fun copiesTheWholeFileInChunks() {
        val bytes = ByteArray(100_000) { (it % 251).toByte() }
        val out = ByteArrayOutputStream()
        assertTrue(PrintPages.copyUnlessCancelled(ByteArrayInputStream(bytes), out, { false }, 4096))
        assertArrayEquals(bytes, out.toByteArray())
    }

    @Test
    fun stopsWhenCancelled() {
        val bytes = ByteArray(100_000)
        val out = ByteArrayOutputStream()
        var checks = 0
        val done = PrintPages.copyUnlessCancelled(
            ByteArrayInputStream(bytes),
            out,
            { ++checks > 3 },
            4096,
        )
        assertFalse(done)
        assertEquals(3 * 4096, out.size())
    }
}
