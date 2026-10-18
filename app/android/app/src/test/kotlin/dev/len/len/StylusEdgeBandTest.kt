package dev.len.len

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StylusEdgeBandTest {
    // 200 dp and 24 dp at density 2.
    private fun band() = StylusEdgeBand(400, 48f)

    @Test
    fun centresTheBandOnTheStylus() {
        val b = band()
        assertTrue(b.follow(1000f, 2000))
        assertTrue(b.placed)
        assertEquals(800, b.top)
        assertEquals(1200, b.bottom)
    }

    @Test
    fun staysInsideTheView() {
        val b = band()
        b.follow(50f, 2000)
        assertEquals(0, b.top)
        assertEquals(400, b.bottom)
        b.follow(1990f, 2000)
        assertEquals(1600, b.top)
        assertEquals(2000, b.bottom)
    }

    @Test
    fun neverTallerThanTheCapOrTheView() {
        val b = band()
        b.follow(100f, 300)
        assertEquals(0, b.top)
        assertEquals(300, b.bottom)
    }

    @Test
    fun followsOnlyPastTheStep() {
        val b = band()
        b.follow(1000f, 2000)
        assertFalse(b.follow(1040f, 2000))
        assertFalse(b.follow(952f, 2000))
        assertEquals(800, b.top)
        assertTrue(b.follow(1049f, 2000))
        assertEquals(849, b.top)
        // Measured from where it was last placed, not from the last sample.
        assertFalse(b.follow(1090f, 2000))
    }

    @Test
    fun aResizedViewPlacesItAgain() {
        val b = band()
        b.follow(1100f, 2000)
        assertTrue(b.follow(1100f, 1200))
        assertEquals(800, b.top)
        assertEquals(1200, b.bottom)
    }

    @Test
    fun clearingSaysWhetherThereWasOne() {
        val b = band()
        assertFalse(b.clear())
        b.follow(500f, 2000)
        assertTrue(b.clear())
        assertFalse(b.placed)
        assertFalse(b.clear())
        assertTrue(b.follow(500f, 2000))
    }
}
