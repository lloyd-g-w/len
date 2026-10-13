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
