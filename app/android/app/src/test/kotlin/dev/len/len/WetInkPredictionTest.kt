package dev.len.len

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Replays the Ink Lab recordings (`test/inklab/recordings`, every `.leninput`)
 * sample by sample, as the overlay sees them with unbuffered dispatch (the
 * last sample of a contact is its ACTION_UP), through a JVM model of the
 * androidx Kalman predictor ([KalmanModel]), and measures how far the drawn
 * prediction strays from where the pen really went: BEFORE (every predicted
 * point up to 20 ms ahead, the old overlay) against AFTER ([WetInkPrediction]).
 * Prints a table (docs/INK_LAB.md, "Prediction") and keeps AFTER within
 * bounds. Run from app/: `tool/wet_ink_check/unit_test.sh`.
 */
class WetInkPredictionTest {
    /** One contact: samples in physical px, normalised pressure, ms; the last one is the pen-up. */
    class Contact(val x: DoubleArray, val y: DoubleArray, val p: DoubleArray, val t: DoubleArray, val penPx: Double) {
        val size get() = t.size

        /** The drawn radius at pressure [p]: Dart's radii are `width / 2 × (0.975 + 0.65 p)`. */
        fun radius(p: Double) = penPx / 2 * (0.975 + 0.65 * p.coerceIn(0.0, 1.0))

        /** The nominal stroke width (px): twice the radius at pressure 0.5. */
        val width get() = 2 * radius(0.5)
    }

    private fun recordingsDir(): File =
        listOf("test/inklab/recordings", "../../test/inklab/recordings").map(::File).first { it.isDirectory }

    private val recordings: Map<String, List<Contact>> by lazy {
        recordingsDir().listFiles { f -> f.name.endsWith(".leninput") }!!.sortedBy { it.name }
            .associate { it.name.removeSuffix(".leninput") to contactsOf(it) }
    }

    @Test
    fun predictionStaysOnThePath() {
        val before = Policy("before") { raw, n, _, _, out -> rawUpTo(raw, n, BEFORE_MS, out) }
        val prediction = WetInkPrediction()
        val after = Policy("after", prediction) { raw, n, r, _, out -> prediction.filter(raw, n, r, out) }
        val groups = linkedMapOf(
            "real" to recordings.filterKeys { it.startsWith("real") }.values.flatten(),
            "sim" to recordings.filterKeys { it.startsWith("sim") }.values.flatten(),
        )
        val results = HashMap<String, Stats>()
        println("Prediction replay (${recordings.keys.joinToString()}): error = distance (px, ×width) of drawn")
        println("predicted points from the real remaining path; lead = how far ahead (ms) it stays within 0.25 width.")
        for ((name, contacts) in groups) {
            val w = contacts.map { it.width }.average()
            println("-- $name: ${contacts.size} contacts, ${contacts.sumOf { it.size }} events, width ≈ ${"%.2f".format(w)} px")
            println(String.format("%-28s %-26s %-26s", "", "before (20 ms, all)", "after"))
            val b = replay(contacts, before)
            val a = replay(contacts, after)
            results["$name.before"] = b
            results["$name.after"] = a
            for (row in Stats.rows) println(String.format("%-28s %-26s %-26s", row, b.show(row), a.show(row)))
        }
        for (g in groups.keys) {
            val a = results["$g.after"]!!
            val b = results["$g.before"]!!
            assertTrue("$g: pen-up overshoot p95 ${a.penUp.q(0.95)} W", a.penUp.q(0.95) <= 0.35)
            assertTrue("$g: turn overshoot p95 ${a.turn.q(0.95)} W", a.turn.q(0.95) <= 0.6)
            assertTrue("$g: overall p95 ${a.all.q(0.95)} W", a.all.q(0.95) <= 0.35)
            assertTrue("$g: pen-up max not worse", a.penUp.max() <= b.penUp.max())
            assertTrue("$g: keeps a lead (${a.leadMs.mean()} ms)", a.leadMs.mean() >= 2.0)
        }
    }

    /**
     * The old tip also drew a line from the end of the ink to the newest raw
     * sample after the pen-up, though the model may have cut the pen-up hook
     * (or thinned the last samples) there: ink Flutter never draws, shown
     * until the overlay lets go of the stroke. Measures how far that line
     * reached past the final ink on the shared goldens (the lifted tip is
     * now empty).
     */
    @Test
    fun liftedTipAddsNoInk() {
        for (name in listOf("sim_hooks", "real_spen_01")) {
            var radii = DoubleArray(0)
            var shape: WetInkShape? = null
            var model: WetInkModel? = null
            val past = Dist()
            val text = javaClass.classLoader!!.getResource("wet_ink/$name.ev")!!.readText()
            for (line in text.lines()) {
                val f = line.split(' ')
                when (f[0]) {
                    "S" -> radii = f.drop(1).map { it.toDouble() }.toDoubleArray()
                    "H" -> shape = WetInkShape.of(f.drop(1).map { it.toDouble() }.toDoubleArray())
                    "B" -> model = WetInkModel(radii, shape!!, 8.3)
                    "A" -> {
                        val m = model!!
                        val x = f[1].toDouble()
                        val y = f[2].toDouble()
                        m.add(x, y, f[3].toDouble(), f[4].toLong(), f[5] == "1")
                        if (f[5] != "1" || m.samples.isEmpty()) continue
                        val h = m.segments(0, m.samples.size)
                        // How far the raw sample lies outside the final ink's circles.
                        var outside = Double.MAX_VALUE
                        for (k in 0 until h.size / 3) {
                            outside = min(outside, dist(x - h[k * 3], y - h[k * 3 + 1]) - h[k * 3 + 2])
                        }
                        past.add(max(0.0, outside))
                    }
                }
            }
            println("Lifted tip, old line to the raw pen-up sample, $name: ${past.size} contacts, outside the final ink by up to %.1f px".format(past.max()))
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Replay

    /** What to draw from the raw prediction: (raw, n, tip radius, contact, out) → points written. */
    class Policy(
        val name: String,
        val prediction: WetInkPrediction? = null,
        val draw: (FloatArray, Int, Double, Contact, FloatArray) -> Int,
    )

    /** Samples of the error distributions, in stroke widths. */
    class Dist {
        private val v = ArrayList<Double>()
        fun add(x: Double) = v.add(x)
        fun q(f: Double): Double {
            if (v.isEmpty()) return 0.0
            val s = v.sorted()
            return s[min(s.size - 1, (f * s.size).toInt())]
        }
        fun max() = v.maxOrNull() ?: 0.0
        fun mean() = if (v.isEmpty()) 0.0 else v.average()
        val size get() = v.size
    }

    class Stats(val widthPx: Double) {
        val penUp = Dist()
        val turn = Dist()
        val all = Dist()
        val leadMs = Dist()
        val leadPx = Dist()
        var flicks = 0

        fun show(row: String): String {
            fun d(x: Dist) = "%.2f/%.2f/%.2f W".format(x.q(0.5), x.q(0.95), x.max())
            return when (row) {
                ROWS[0] -> d(penUp) + " (${penUp.size})"
                ROWS[1] -> "%.1f/%.1f/%.1f px".format(penUp.q(0.5) * widthPx, penUp.q(0.95) * widthPx, penUp.max() * widthPx)
                ROWS[2] -> d(turn) + " (${turn.size})"
                ROWS[3] -> d(all) + " (${all.size})"
                ROWS[4] -> "$flicks"
                ROWS[5] -> "%.1f ms, %.1f px".format(leadMs.mean(), leadPx.mean())
                else -> ""
            }
        }

        companion object {
            private val ROWS = listOf(
                "pen-up p50/p95/max",
                "  (in px)",
                "turns p50/p95/max",
                "all events p50/p95/max",
                "events off by > 0.5 W",
                "steady lead (mean)",
            )
            val rows get() = ROWS
        }
    }

    private fun replay(contacts: List<Contact>, policy: Policy): Stats {
        val stats = Stats(contacts.map { it.width }.average())
        val raw = FloatArray(3 * MAX_RAW)
        val out = FloatArray(2 * MAX_RAW)
        for (c in contacts) {
            val kalman = KalmanModel()
            policy.prediction?.reset()
            val w = c.width
            for (i in 0 until c.size) {
                kalman.record(c.x[i], c.y[i], c.p[i], c.t[i].toLong())
                policy.prediction?.add(c.x[i], c.y[i], c.p[i], c.t[i])
                // The down only starts the predictor; the up draws no prediction.
                if (i == 0 || i == c.size - 1) continue
                val n = kalman.predict(BEFORE_MS.toInt(), c.t[i].toLong(), raw)
                val m = policy.draw(raw, n, c.radius(c.p[i]), c, out)
                val err = error(c, i, out, m) / w
                stats.all.add(err)
                if (err > 0.5) stats.flicks++
                val penUp = c.t[c.size - 1] - c.t[i] <= WINDOW_MS
                val turn = !penUp && turnsAhead(c, i)
                if (penUp) stats.penUp.add(err)
                if (turn) stats.turn.add(err)
                if (!penUp && !turn && speed(c, i) >= STEADY_PX_PER_MS) {
                    val (ms, px) = lead(c, i, out, m, 0.25 * w)
                    stats.leadMs.add(ms)
                    stats.leadPx.add(px)
                }
            }
        }
        return stats
    }

    /** The old overlay: every point up to [ms] ahead. */
    private fun rawUpTo(raw: FloatArray, n: Int, ms: Double, out: FloatArray): Int {
        var m = 0
        for (i in 0 until n) {
            if (raw[i * 3 + 2] > ms) break
            out[m * 2] = raw[i * 3]
            out[m * 2 + 1] = raw[i * 3 + 1]
            m++
        }
        return m
    }

    /** The last index of the real path [WINDOW_MS] × 2 after sample [i] (where a prediction may land). */
    private fun futureEnd(c: Contact, i: Int): Int {
        var j = i
        while (j < c.size - 1 && c.t[j + 1] - c.t[i] <= 2 * WINDOW_MS + 30) j++
        return j
    }

    /** The largest distance (px) of the drawn points from the real path from sample [i] on. */
    private fun error(c: Contact, i: Int, out: FloatArray, m: Int): Double {
        val end = futureEnd(c, i)
        var worst = 0.0
        for (k in 0 until m) worst = max(worst, project(c, i, end, out[k * 2].toDouble(), out[k * 2 + 1].toDouble()).first)
        return worst
    }

    /** (distance, time) of the nearest point to (x, y) on the path from sample [i] to [end]. */
    private fun project(c: Contact, i: Int, end: Int, x: Double, y: Double): Pair<Double, Double> {
        if (end == i) return Pair(dist(x - c.x[i], y - c.y[i]), c.t[i])
        var best = Double.MAX_VALUE
        var bestT = c.t[i]
        for (j in i until end) {
            val ax = c.x[j]
            val ay = c.y[j]
            val dx = c.x[j + 1] - ax
            val dy = c.y[j + 1] - ay
            val len2 = dx * dx + dy * dy
            val f = if (len2 > 0) (((x - ax) * dx + (y - ay) * dy) / len2).coerceIn(0.0, 1.0) else 0.0
            val d = dist(x - ax - dx * f, y - ay - dy * f)
            if (d < best) {
                best = d
                bestT = c.t[j] + (c.t[j + 1] - c.t[j]) * f
            }
        }
        return Pair(best, bestT)
    }

    /**
     * How far ahead (ms of the real path, px from the newest sample) the drawn
     * points get before one leaves the path by more than [tolerance].
     */
    private fun lead(c: Contact, i: Int, out: FloatArray, m: Int, tolerance: Double): Pair<Double, Double> {
        val end = futureEnd(c, i)
        var ms = 0.0
        var px = 0.0
        for (k in 0 until m) {
            val x = out[k * 2].toDouble()
            val y = out[k * 2 + 1].toDouble()
            val (d, t) = project(c, i, end, x, y)
            if (d > tolerance) break
            ms = max(ms, t - c.t[i])
            px = max(px, dist(x - c.x[i], y - c.y[i]))
        }
        return Pair(ms, px)
    }

    /** Position at time [t] (interpolated, clamped to the contact). */
    private fun at(c: Contact, t: Double): Pair<Double, Double> {
        if (t <= c.t[0]) return Pair(c.x[0], c.y[0])
        for (j in 1 until c.size) {
            if (c.t[j] >= t) {
                val span = c.t[j] - c.t[j - 1]
                val f = if (span > 0) (t - c.t[j - 1]) / span else 1.0
                return Pair(c.x[j - 1] + (c.x[j] - c.x[j - 1]) * f, c.y[j - 1] + (c.y[j] - c.y[j - 1]) * f)
            }
        }
        return Pair(c.x[c.size - 1], c.y[c.size - 1])
    }

    /** px/ms over the last 6 ms. */
    private fun speed(c: Contact, i: Int): Double {
        val (x, y) = at(c, c.t[i] - 6)
        return dist(c.x[i] - x, c.y[i] - y) / 6
    }

    /**
     * Whether the real path turns sharply within [WINDOW_MS] after sample
     * [i]: a chord to a later point (at least half a width away) deviates
     * more than 30° from the direction of the last 6 ms (≈ 60° of turn).
     */
    private fun turnsAhead(c: Contact, i: Int): Boolean {
        val (bx, by) = at(c, c.t[i] - 6)
        val ix = c.x[i] - bx
        val iy = c.y[i] - by
        val il = dist(ix, iy)
        if (il < 0.5 * c.width) return false
        var j = i + 1
        while (j < c.size && c.t[j] - c.t[i] <= WINDOW_MS) {
            val fx = c.x[j] - c.x[i]
            val fy = c.y[j] - c.y[i]
            val fl = dist(fx, fy)
            if (fl >= 0.5 * c.width && acos(((ix * fx + iy * fy) / (il * fl)).coerceIn(-1.0, 1.0)) > Math.toRadians(30.0)) return true
            j++
        }
        return false
    }

    private fun dist(x: Double, y: Double) = sqrt(x * x + y * y)

    // ---------------------------------------------------------------------------------------------
    // The androidx Kalman predictor (input-motionprediction `SinglePointerPredictor` and
    // `PointerKalmanFilter`, balanced strategy, stylus), as the overlay's predictor where the
    // device has no system one. Positions in px, one filter step per sample.

    class KalmanModel {
        private val fx = Axis()
        private val fy = Axis()
        private val fp = Axis()
        private var iterations = 0
        private var lastX = Double.NaN
        private var lastY = Double.NaN
        private var lastSeen = 0L
        private val rates = ArrayList<Double>()
        private var rateMs = 0.0
        private var lastPredicted = 0.0

        fun record(x: Double, y: Double, p: Double, timeMs: Long) {
            // `SinglePointerPredictor.update`: same position soon after is ignored.
            if (x == lastX && y == lastY && timeMs <= lastSeen + 20) return
            if (iterations == 0) {
                fx.init(x); fy.init(y); fp.init(p)
            } else {
                fx.step(x); fy.step(y); fp.step(p)
            }
            iterations++
            lastX = x
            lastY = y
            if (rates.size < 20 && lastSeen > 0) {
                rates.add((timeMs - lastSeen).toDouble())
                rateMs = rates.average()
            }
            lastSeen = timeMs
        }

        /** Writes (x, y, ms after [nowMs]) triples into [out]; returns how many. */
        fun predict(targetMs: Int, nowMs: Long, out: FloatArray): Int {
            if (iterations < 4 || rateMs <= 0) return 0
            var px = lastX
            var py = lastY
            var vx = fx.s[1]
            var vy = fy.s[1]
            var ax = fx.s[2]
            var ay = fy.s[2]
            val jx = fx.s[3]
            val jy = fy.s[3]
            var pressure = fp.s[0]
            val jank = sqrt(jx * jx + jy * jy)
            // Stylus: speed factor 1, jank factor from 0.1 to 0.2 px/sample³.
            val confidence = 1 - ((jank - 0.1) / 0.1).coerceIn(0.0, 1.0)
            val samples = ceil(targetMs / rateMs * confidence).toInt()
            var time = lastSeen.toDouble()
            var next = lastSeen + rateMs
            var n = 0
            var k = 0
            while ((k < samples || next <= lastPredicted) && n < MAX_RAW) {
                ax += jx * 0.1; ay += jy * 0.1
                vx += ax * 0.5; vy += ay * 0.5
                px += vx; py += vy
                pressure = (pressure + fp.s[1]).coerceIn(0.0, 1.0)
                out[n * 3] = px.toFloat()
                out[n * 3 + 1] = py.toFloat()
                out[n * 3 + 2] = (next.toLong() - nowMs).toFloat()
                n++
                time = next
                next += rateMs
                k++
            }
            lastPredicted = time
            return n
        }

        /** One axis: position, velocity, acceleration, jerk; `PointerKalmanFilter.createAxisKalmanFilter`. */
        class Axis {
            val s = DoubleArray(4)
            private val p = DoubleArray(16)
            private val f = doubleArrayOf(1.0, 1.0, 0.5, 0.16, 0.0, 1.0, 1.0, 0.5, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0)
            private val q = DoubleArray(16).also {
                val g = doubleArrayOf(0.16, 0.5, 1.0, 1.0)
                for (r in 0 until 4) for (c in 0 until 4) it[r * 4 + c] = g[r] * g[c] * 0.01
            }

            fun init(z: Double) {
                s.fill(0.0)
                s[0] = z
                p.fill(0.0)
                for (k in 0 until 4) p[k * 5] = 1.0
            }

            fun step(z: Double) {
                // Predict: s = F s, P = F P Fᵀ + Q.
                val ns = DoubleArray(4) { r -> (0 until 4).sumOf { f[r * 4 + it] * s[it] } }
                val fp = DoubleArray(16) { (0 until 4).sumOf { k -> f[(it / 4) * 4 + k] * p[k * 4 + it % 4] } }
                for (r in 0 until 4) for (c in 0 until 4) {
                    p[r * 4 + c] = (0 until 4).sumOf { k -> fp[r * 4 + k] * f[c * 4 + k] } + q[r * 4 + c]
                }
                ns.copyInto(s)
                // Update with z (H = [1 0 0 0], R = 1).
                val sInv = 1.0 / (p[0] + 1.0)
                val gain = DoubleArray(4) { p[it * 4] * sInv }
                val y = z - s[0]
                for (r in 0 until 4) s[r] += gain[r] * y
                val row0 = DoubleArray(4) { p[it] }
                for (r in 0 until 4) for (c in 0 until 4) p[r * 4 + c] -= gain[r] * row0[c]
            }
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Recordings

    /**
     * The stylus contacts of a recording, in physical px. A contact's batch
     * samples (`"b"`, every digitiser sample, µs) when the recording has all
     * of them, else its Flutter pointer events (`"p"`, logical px × dpr, ms):
     * the real recordings' batches are incomplete.
     */
    private fun contactsOf(file: File): List<Contact> {
        val json = Json(file.readText()).value() as Map<*, *>
        val meta = json["meta"] as Map<*, *>
        val dpr = (meta["dpr"] as Double)
        val penPx = ((meta["pen"] as Map<*, *>)["width"] as Double) * dpr
        val batches = HashMap<Long, MutableList<List<*>>>()
        val strokes = ArrayList<MutableList<List<*>>>()
        var current: MutableList<List<*>>? = null
        for (e in json["entries"] as List<*>) {
            e as List<*>
            when (e[0]) {
                "b" -> for (b in e.drop(2)) {
                    b as List<*>
                    val down = Math.round((b[1] as Double) / 1000)
                    @Suppress("UNCHECKED_CAST")
                    batches.getOrPut(down) { ArrayList() }.addAll(b[3] as List<List<*>>)
                }
                "p" -> {
                    if ((e[3] as Double).toInt() != STYLUS) continue
                    when ((e[2] as Double).toInt()) {
                        DOWN -> current = arrayListOf(e).also { strokes.add(it) }
                        MOVE -> current?.add(e)
                        UP -> { current?.add(e); current = null }
                        CANCEL -> { current?.let { strokes.remove(it) }; current = null }
                    }
                }
            }
        }
        return strokes.filter { it.size >= 2 && (it.last()[2] as Double).toInt() == UP }.map { s ->
            val down = Math.round((s[0][6] as Double) / 1000)
            val b = batches[down]
            if (b != null && b.size >= s.size) {
                Contact(
                    DoubleArray(b.size) { b[it][1] as Double },
                    DoubleArray(b.size) { b[it][2] as Double },
                    DoubleArray(b.size) { b[it][3] as Double },
                    DoubleArray(b.size) { Math.round((b[it][0] as Double) / 1000).toDouble() },
                    penPx,
                )
            } else {
                Contact(
                    DoubleArray(s.size) { (s[it][7] as Double) * dpr },
                    DoubleArray(s.size) { (s[it][8] as Double) * dpr },
                    DoubleArray(s.size) {
                        val min = s[it][12] as Double
                        val range = (s[it][13] as Double) - min
                        if (range > 0) ((s[it][11] as Double) - min) / range else 0.5
                    },
                    DoubleArray(s.size) { Math.round((s[it][6] as Double) / 1000).toDouble() },
                    penPx,
                )
            }
        }
    }

    /** Just enough JSON: objects, arrays, numbers (as Double), strings, true/false/null. */
    private class Json(private val s: String) {
        private var i = 0

        fun value(): Any? {
            ws()
            return when (val c = s[i]) {
                '{' -> {
                    i++
                    val m = LinkedHashMap<String, Any?>()
                    ws()
                    if (s[i] == '}') { i++; return m }
                    while (true) {
                        ws()
                        val k = string()
                        ws(); i++ // ':'
                        m[k] = value()
                        ws()
                        if (s[i++] == '}') return m
                    }
                    @Suppress("UNREACHABLE_CODE") m
                }
                '[' -> {
                    i++
                    val l = ArrayList<Any?>()
                    ws()
                    if (s[i] == ']') { i++; return l }
                    while (true) {
                        l.add(value())
                        ws()
                        if (s[i++] == ']') return l
                    }
                    @Suppress("UNREACHABLE_CODE") l
                }
                '"' -> string()
                't' -> { i += 4; true }
                'f' -> { i += 5; false }
                'n' -> { i += 4; null }
                else -> {
                    val start = i
                    while (i < s.length && (s[i].isDigit() || s[i] in "+-.eE")) i++
                    if (start == i) error("bad JSON at $i: '$c'")
                    s.substring(start, i).toDouble()
                }
            }
        }

        private fun string(): String {
            i++ // '"'
            val b = StringBuilder()
            while (s[i] != '"') {
                if (s[i] == '\\') {
                    i++
                    when (s[i]) {
                        'n' -> b.append('\n')
                        't' -> b.append('\t')
                        'u' -> { b.append(s.substring(i + 1, i + 5).toInt(16).toChar()); i += 4 }
                        else -> b.append(s[i])
                    }
                } else {
                    b.append(s[i])
                }
                i++
            }
            i++
            return b.toString()
        }

        private fun ws() {
            while (i < s.length && s[i].isWhitespace()) i++
        }
    }

    companion object {
        /** The old overlay's horizon (ms). */
        const val BEFORE_MS = 20.0

        /** Pen-up and turn windows (ms): the old horizon, so both policies are judged on the same events. */
        const val WINDOW_MS = 20.0

        /** Steady motion, for the lead: at least this fast (px/ms). */
        const val STEADY_PX_PER_MS = 0.1

        const val MAX_RAW = WetInkPrediction.MAX_POINTS

        // Flutter's PointerDeviceKind.stylus and PointerType indices (lib/ink/lab/input_recording.dart).
        const val STYLUS = 2
        const val DOWN = 0
        const val MOVE = 1
        const val UP = 2
        const val CANCEL = 3
    }
}
