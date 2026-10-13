// Runs the Kotlin wet-ink model (android/.../WetInkModel.kt) on the vectors
// written by test/inklab/tools/wet_ink_vectors_test.dart and compares its
// answers with the Dart model's. See check.sh.
import dev.len.len.WetInkModel
import dev.len.len.WetInkShape
import java.io.File
import kotlin.math.abs
import kotlin.system.exitProcess

fun main(args: Array<String>) {
    var worst = 0.0
    var queries = 0
    var mismatches = 0
    for (path in args) {
        var radii = DoubleArray(0)
        var shape: WetInkShape? = null
        var model: WetInkModel? = null
        val expected = File(path.removeSuffix(".ev") + ".expected").readLines()
        var q = 0
        for (line in File(path).readLines()) {
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
                    queries++
                    if (got.size != want.size || got[0] != want[0]) {
                        if (mismatches++ < 10) println("$path query ${q - 1}: ${got.size} values, expected ${want.size}")
                        continue
                    }
                    for (i in got.indices) worst = maxOf(worst, abs(got[i] - want[i]))
                }
            }
        }
    }
    println("$queries queries, $mismatches mismatched, largest difference $worst")
    if (mismatches > 0 || worst > 1e-9) exitProcess(1)
}
