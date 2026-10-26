package dev.len.len

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * The Kotlin wet-ink model against the shared golden written by the Dart
 * model (`test/inklab/wet_ink_golden_test.dart`): the overlay must draw
 * exactly what the Ink Lab measures. `tool/wet_ink_check/check.sh` runs the
 * same comparison over every Ink Lab case and recording.
 */
class WetInkModelTest {
    @Test
    fun simulatedHooksMatchTheDartModel() = check("sim_hooks")

    @Test
    fun realSPenWritingMatchesTheDartModel() = check("real_spen_01")

    /** The stabiliser's longest string (80 px at 100 %). */
    @Test
    fun aLongStabiliserStringMatchesTheDartModel() = check("sim_cursive_string")

    /**
     * At the lift the stroke stops where the stabiliser's ink is (within the
     * points' spacing), up to the string short of the pen: nothing catches up.
     */
    @Test
    fun theLiftStopsWhereTheInkIs() {
        val ev = lines("sim_cursive_string.ev").map { it.split(' ') }
        val radii = ev.first { it[0] == "S" }.drop(1).map { it.toDouble() }.toDoubleArray()
        val shape = WetInkShape.of(ev.first { it[0] == "H" }.drop(1).map { it.toDouble() }.toDoubleArray())!!
        val model = WetInkModel(radii, shape, 8.3)
        val ink = PenStabiliser(shape)
        // The last contact's samples.
        val adds = ev.drop(ev.indexOfLast { it[0] == "B" }).filter { it[0] == "A" }
        for (f in adds) {
            val x = f[1].toDouble()
            val y = f[2].toDouble()
            model.add(x, y, f[3].toDouble(), f[4].toLong(), f[5] == "1")
            ink.add(x, y)
        }
        assertTrue(model.lifted)
        val end = model.samples.last()
        val fromInk = WetInkModel.dist(end.x - ink.inkX, end.y - ink.inkY)
        assertTrue("the end is the ink's ($fromInk px off)", fromInk <= shape.minSpacing + 1e-9)
        val last = adds.last()
        val fromPen = WetInkModel.dist(end.x - last[1].toDouble(), end.y - last[2].toDouble())
        assertTrue("within the string of the pen ($fromPen px)", fromPen <= shape.stabiliserRadius + shape.minSpacing)
        assertTrue("short of the pen ($fromPen px)", fromPen > 0.25 * shape.stabiliserRadius)

        // A tap still leaves its point, under the nib.
        val tap = WetInkModel(radii, shape, 8.3)
        tap.add(100.0, 100.0, 0.5, 0)
        tap.add(100.0, 100.0, 0.5, 30, lift = true)
        assertEquals(1, tap.samples.size)
        assertEquals(100.0, tap.samples[0].x, 0.0)
        assertEquals(100.0, tap.samples[0].y, 0.0)
    }

    @Test
    fun flatAndTaperedEndsMatchTheDartModel() {
        for (name in listOf("sim_hooks", "real_spen_01")) {
            check("${name}_flat")
            check("${name}_tapered")
        }
    }

    private fun lines(name: String): List<String> =
        javaClass.classLoader!!.getResource("wet_ink/$name")!!.readText().lines().filter { it.isNotEmpty() }

    private fun check(name: String) {
        val expected = lines("$name.expected")
        var radii = DoubleArray(0)
        var shape: WetInkShape? = null
        var model: WetInkModel? = null
        var q = 0
        for (line in lines("$name.ev")) {
            val f = line.split(' ')
            when (f[0]) {
                "S" -> radii = f.drop(1).map { it.toDouble() }.toDoubleArray()
                "H" -> shape = WetInkShape.of(f.drop(1).map { it.toDouble() }.toDoubleArray())
                "B" -> model = WetInkModel(radii, shape!!, 8.3)
                "A" -> model!!.add(f[1].toDouble(), f[2].toDouble(), f[3].toDouble(), f[4].toLong(), f[5] == "1")
                "Q" -> {
                    val m = model!!
                    if (f[3].toDouble() >= 0) m.commit(f[4].toDouble())
                    val from = m.tailStart(f[1].toDouble(), f[2].toDouble(), f[3].toDouble())
                    val got = mutableListOf(from.toDouble())
                    if (from < m.samples.size) {
                        val segments = m.segments(from, m.samples.size)
                        got.add((if (m.flatStart) 1.0 else 0.0) + (if (m.flatEnd) 2.0 else 0.0))
                        got.add(m.cuts.size.toDouble())
                        for (c in m.cuts) got.addAll(listOf(c.piece.toDouble(), c.px, c.py, c.nx, c.ny))
                        got.add(m.sweeps.size.toDouble())
                        for (w in m.sweeps) {
                            got.add(w.piece.toDouble())
                            got.addAll(w.a.toList())
                            got.addAll(w.b.toList())
                        }
                        got.addAll(segments.toList())
                    }
                    val want = expected[q++].split(' ').map { it.toDouble() }
                    assertEquals("$name query ${q - 1}: values", want.size, got.size)
                    for (i in got.indices) {
                        assertTrue("$name query ${q - 1} value $i: ${got[i]} ≠ ${want[i]}", abs(got[i] - want[i]) < 1e-9)
                    }
                }
            }
        }
        assertEquals("every expected answer was checked", expected.size, q)
        assertTrue("the golden has answers", q >= 10)
    }
}
