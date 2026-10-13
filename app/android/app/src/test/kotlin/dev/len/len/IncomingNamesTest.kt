package dev.len.len

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Names and schemes of files other apps hand to Len ([IncomingFiles]). */
class IncomingNamesTest {
    @Test
    fun keepsAnOrdinaryName() {
        assertEquals("Lecture 3.pdf", IncomingNames.safe("Lecture 3.pdf"))
    }

    @Test
    fun dropsPathsAndTraversal() {
        assertEquals("passwd", IncomingNames.safe("../../etc/passwd"))
        assertEquals("len.db", IncomingNames.safe("/data/data/dev.len.len/files/len.db"))
        assertEquals("file", IncomingNames.safe(".."))
        assertEquals("file", IncomingNames.safe("dir/"))
    }

    @Test
    fun replacesCharactersFileSystemsReject() {
        assertEquals("a_b_c_.png", IncomingNames.safe("a\\b:c?.png"))
        assertEquals("x_y.pdf", IncomingNames.safe("x\ny.pdf"))
    }

    @Test
    fun isNeverHiddenNorEmpty() {
        assertEquals("notes.len", IncomingNames.safe(".notes.len"))
        assertEquals("file", IncomingNames.safe("   "))
    }

    @Test
    fun keepsTheExtensionOfLongNames() {
        val safe = IncomingNames.safe("a".repeat(300) + ".pdf")
        assertEquals(120, safe.length)
        assertTrue(safe.endsWith(".pdf"))
    }

    @Test
    fun readsOnlyContentUris() {
        assertTrue(IncomingNames.acceptsScheme("content"))
        assertFalse(IncomingNames.acceptsScheme("file"))
        assertFalse(IncomingNames.acceptsScheme(null))
    }
}
