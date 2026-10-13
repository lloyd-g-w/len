package dev.len.len

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The polygon `WetInkLayer` draws for a piece cut off at a flat end. */
class WetInkEndsTest {
    private fun area(p: FloatArray): Double {
        var a = 0.0
        val n = p.size / 2
        for (i in 0 until n) {
            val j = (i + 1) % n
            a += p[2 * i].toDouble() * p[2 * j + 1] - p[2 * j].toDouble() * p[2 * i + 1]
        }
        return a / 2
    }

    @Test
    fun aPieceCutAtItsStartEndsSquareThere() {
        // Circles of radius 2 at (0, 0) and (1, 0), cut at x = 0 (facing −x).
        val p = WetInkEnds.cutHull(0f, 0f, 2f, 1f, 0f, 2f, floatArrayOf(0f, 0f, -1f, 0f), 0.01f)
        var minX = Float.MAX_VALUE
        var maxX = -Float.MAX_VALUE
        for (i in 0 until p.size / 2) {
            minX = minOf(minX, p[2 * i])
            maxX = maxOf(maxX, p[2 * i])
        }
        assertEquals(0f, minX, 1e-5f)
        assertEquals(3f, maxX, 1e-3f)
        // The 1 × 4 between the centres and the far half of circle b.
        assertEquals(Math.PI * 2 + 4, area(p), 0.1)
        // Wound clockwise on screen (y down), as the overlay's circles.
        assertTrue(area(p) > 0)
    }

    @Test
    fun aPieceBeyondTheLineIsGone() {
        val p = WetInkEnds.cutHull(5f, 0f, 1f, 6f, 0f, 1f, floatArrayOf(0f, 0f, 1f, 0f), 0.01f)
        assertEquals(0, p.size)
    }
}
