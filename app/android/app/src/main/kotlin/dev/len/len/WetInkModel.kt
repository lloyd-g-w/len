package dev.len.len

import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

// What the low-latency overlay draws, as a pure function of the samples and
// the rules Dart sends (no Android types, so it can be checked on a plain
// JVM). This is a line-for-line port of `lib/ink/lab/wet_ink_model.dart`
// (and of the parts of `StrokeShaper` and `HookFinder` it uses); the Ink Lab
// measures that Dart model, so keep the two in step.

/** The rules of Dart's `WetInkShape`, in the order `WetInkShape.toList` sends them. */
class WetInkShape(v: DoubleArray) {
    val minSpacing = v[0]
    val keepExtreme = v[1]
    val pressureKeep = v[2]
    val radiusSigma = v[3]
    val slope = v[4]
    val settleStart = v[5]
    val levelStart = v[6]
    val settleEnd = v[7]
    val levelEnd = v[8]
    val hookStart = v[9]
    val hookEnd = v[10]
    val hookBody = v[11]
    val hookLocal = v[12]
    val step = v[13]
    val dedupe = v[14]
    val fit = v[15].toInt()
    val cornerK = v[16].toInt()

    /**
     * With the stabiliser on, live ink shows only the final line
     * (`ShapeParams.lag`): the samples the tip rules keep back (0: stabiliser
     * off), and the start rules' reach (samples).
     */
    val lag = v[17].toInt()
    val startReach = v[18].toInt()

    /** Butt caps instead of round ones. */
    val flat = v[19] != 0.0

    /** Length over which the start narrows to a point ([Taper]; 0: none). */
    val taperStart = v[20]

    /** With [flat] ends, how many points an end's zone may reach (two widths). */
    val flatReach = v[21].toInt()
    val kernel: DoubleArray = v.copyOfRange(FIELDS, v.size)
    val kernelK = (kernel.size - 1) / 2

    companion object {
        const val FIELDS = 22

        /** The rules in [v], or null when it is not a valid list. */
        fun of(v: DoubleArray): WetInkShape? =
            if (v.size > FIELDS && (v.size - FIELDS) % 2 == 1) WetInkShape(v) else null
    }
}

/**
 * A device pressure normalised to 0..1 as a stroke stores it: clamped to
 * 0.05..1, then Dart's `PressureCurve` (`4p / (3p + 1)`, 0.2 is medium).
 */
fun strokePressure(normalised: Double): Double {
    val p = normalised.coerceIn(0.05, 1.0)
    return 4 * p / (3 * p + 1)
}

/** A sample as the overlay keeps it (pressure already smoothed). */
class WetSample(val x: Double, val y: Double, var pressure: Double, val timeMs: Long)

/**
 * The overlay's ink for one contact: which samples are points, their radii
 * and smoothed positions, and which of them to show. See the Dart model's
 * documentation for the rules.
 */
class WetInkModel(
    private val radii: DoubleArray,
    private val shape: WetInkShape,
    private val frameMs: Double,
) {
    /** Whether the stabiliser is on: the ink shows only the final, smoothed line. */
    val stabilised get() = shape.lag > 0

    /** The points drawn: from the end of the pen-down hook, or from pen-down while that is undecided. */
    val samples = ArrayList<WetSample>()

    // Every point of the contact (the hooks are decided on them), and how
    // many of them the pen-down hook drops, once decided (-1: undecided).
    private val allX = DoubleList()
    private val allY = DoubleList()
    private var start = -1

    // When the pen-down hook was trimmed (time of the deciding point; -1:
    // not trimmed), and the largest radius among its points.
    private var trimmedAtMs = -1L
    private var trimmedRadius = 0.0

    // The end taper of the committed stroke (0 until [commit]).
    private var endTaper = 0.0

    /**
     * Ends of the last [segments]: a butt cap at the first point (the
     * stroke's start) and at the last; a lone point with both is a square.
     */
    var flatStart = false
        private set
    var flatEnd = false
        private set

    /**
     * Where the pieces of the last [segments] are cut off at flat ends
     * ([WetInkEnds]); their pieces count from its first triple.
     */
    var cuts: List<WetCut> = emptyList()
        private set

    /**
     * The pieces of the last [segments] drawn as flat nib sweeps in a flat
     * end's zone ([WetInkEnds]), counted as [cuts]' are.
     */
    var sweeps: List<WetSweep> = emptyList()
        private set

    private var pressure = -1.0
    private var hasLast = false
    private var lastX = 0.0
    private var lastY = 0.0
    private val dropped = ArrayList<WetSample>()
    var lifted = false
        private set

    /** Adds a digitiser sample ([pressure] normalised to 0..1); [lift] marks the pen-up one. */
    fun add(x: Double, y: Double, pressure: Double, timeMs: Long, lift: Boolean = false) {
        if (lifted) return
        val norm = strokePressure(pressure)
        if (!lift || this.pressure < 0) {
            this.pressure = if (this.pressure < 0) {
                norm
            } else {
                this.pressure * shape.pressureKeep + norm * (1 - shape.pressureKeep)
            }
        }
        val sample = WetSample(x, y, this.pressure, timeMs)
        if (!hasLast) {
            keep(sample)
        } else if (dist(x - lastX, y - lastY) < shape.minSpacing) {
            dropped.add(sample)
        } else {
            var extreme: WetSample? = null
            var best = shape.keepExtreme
            for (d in dropped) {
                val off = distanceToSegment(d.x, d.y, lastX, lastY, x, y)
                if (off > best) {
                    best = off
                    extreme = d
                }
            }
            dropped.clear()
            if (extreme != null) keep(extreme)
            keep(sample)
        }
        if (lift) lift(timeMs)
    }

    private fun keep(s: WetSample) {
        hasLast = true
        lastX = s.x
        lastY = s.y
        allX.add(s.x)
        allY.add(s.y)
        samples.add(s)
        if (start < 0) decideStart(allX.size, ended = false, atMs = s.timeMs)
    }

    /** Decides the pen-down hook from the first [n] points, if they reach far enough (or [ended]); drops its points. */
    private fun decideStart(n: Int, ended: Boolean, atMs: Long) {
        val cut = startCut(n, ended)
        if (cut < 0) return
        start = cut
        if (cut == 0) return
        trimmedAtMs = atMs
        for (i in 0 until min(cut, samples.size)) trimmedRadius = max(trimmedRadius, radiusAt(samples[i].pressure))
        samples.subList(0, min(cut, samples.size)).clear()
        forget(0)
        arcs.size = 1
    }

    // Causal radii per point (two passes, slope-limited) and arc lengths.
    private val r1 = DoubleList()
    private val r2 = DoubleList()
    private val rs = DoubleList()
    private val arc = DoubleList()

    private fun forget(from: Int) {
        for (l in arrayOf(r1, r2, rs, arc)) {
            if (l.size > from) l.size = max(0, from)
        }
    }

    private fun lift(timeMs: Long) {
        lifted = true
        val n = samples.size
        forget(n - 3)
        for (i in max(1, n - 3) until n) {
            val ceiling = samples[i - 1].pressure
            if (samples[i].pressure > ceiling) samples[i].pressure = ceiling
        }
        // The pen-up hook, on every point (as the outline finds it).
        val all = allX.size
        val keepAll = if (all < 2) all else endKeep(all)
        if (start < 0) decideStart(keepAll, ended = true, atMs = timeMs)
        val keep = max(min(1, samples.size), keepAll - start)
        while (samples.size > keep) samples.removeAt(samples.size - 1)
        forget(keep)
        if (arcs.size > keep - 1) arcs.size = max(1, keep - 1)
    }

    /** Flutter has committed the stroke (`end`), with an end taper [taperEnd] long (0: none). */
    fun commit(taperEnd: Double) {
        endTaper = taperEnd
    }

    fun radiusAt(p: Double): Double {
        if (radii.size == 1) return radii[0]
        val t = p.coerceIn(0.0, 1.0) * (radii.size - 1)
        val i = min(floor(t).toInt(), radii.size - 2)
        return radii[i] + (radii[i + 1] - radii[i]) * (t - i)
    }

    /** The radius of every point: causal smoothing by length, then the start and tip rules. */
    fun pointRadii(): DoubleArray {
        val n = samples.size
        for (i in rs.size until n) {
            val raw = radiusAt(samples[i].pressure)
            if (i == 0) {
                r1.add(raw)
                r2.add(raw)
                rs.add(raw)
                arc.add(0.0)
                continue
            }
            val d = dist(samples[i].x - samples[i - 1].x, samples[i].y - samples[i - 1].y)
            arc.add(arc[i - 1] + d)
            val before = radiusAt(samples[i - 1].pressure)
            val steps = max(1, ceil(d / shape.step).toInt())
            val h = d / steps
            val keep = exp(-2 * h / shape.radiusSigma)
            var a = r1[i - 1]
            var b = r2[i - 1]
            var limited = rs[i - 1]
            for (k in 1..steps) {
                val input = before + (raw - before) * k / steps
                a = a * keep + input * (1 - keep)
                b = b * keep + a * (1 - keep)
                limited = b.coerceIn(limited - shape.slope * h, limited + shape.slope * h)
            }
            r1.add(a)
            r2.add(b)
            rs.add(limited)
        }
        val r = rs.toArray(n)
        if (n == 0) return r
        val total = arc[n - 1]
        for (i in n - 2 downTo 0) {
            if (arc[i] < shape.settleStart) r[i] = min(r[i], r[i + 1])
        }
        level(r, { arc[it] }, shape.levelStart)
        for (i in 1 until n) {
            if (total - arc[i] < shape.settleEnd) r[i] = min(r[i], r[i - 1])
        }
        level(r, { total - arc[it] }, shape.levelEnd)
        return r
    }

    /** Raises the radius within [reach] of an end (distance [fromEnd]) to the radius found at [reach]. */
    private fun level(r: DoubleArray, fromEnd: (Int) -> Double, reach: Double) {
        if (reach <= 0 || r.isEmpty() || arc[r.size - 1] < 2 * reach) return
        var level = -1.0
        var best = Double.POSITIVE_INFINITY
        for (i in r.indices) {
            val d = abs(fromEnd(i) - reach)
            if (fromEnd(i) >= reach && d < best) {
                best = d
                level = r[i]
            }
        }
        if (level < 0) return
        for (i in r.indices) {
            if (fromEnd(i) < reach) r[i] = max(r[i], level)
        }
    }

    /** The samples of a line [length] long Flutter's live ink draws when it
     *  may show [live] (`StrokeOutline.shownOf`): round ends one less, where
     *  the end's tangent is known. */
    private fun shownOf(live: Int, length: Int): Int =
        if (!shape.flat && live < length && live > 2) live - 1 else live

    /**
     * Index of the first point shown at [nowMs], given the progress reported
     * two messages before the latest ([shownUpToMs]) and, after `end`, when
     * it ended ([endedAtMs] ≥ 0). The number of points when nothing shows.
     */
    fun tailStart(nowMs: Double, shownUpToMs: Double, endedAtMs: Double): Int {
        if (endedAtMs >= 0 && nowMs - endedAtMs >= END_FRAMES * frameMs) return samples.size
        var from = samples.size
        while (from > 0 && samples[from - 1].timeMs > shownUpToMs) from--
        if (lifted && samples.isNotEmpty()) from = min(from, samples.size - 1)
        // Flutter still shows the start from pen-down: draw the trimmed start.
        if (trimmedAtMs >= 0 && trimmedAtMs > shownUpToMs && samples.isNotEmpty()) return 0
        if (from == samples.size) return from
        from = max(0, from - 1)
        // Stabiliser on: Flutter's ink ends further back than its newest
        // input (round ends a sample more: shownOf); flat ends: its end's
        // zone has less ink than the line will.
        val lagSamples = shape.kernelK + shape.cornerK + shape.lag + (if (shape.flat) 2 else 3)
        val lagReach = if (shape.lag > 0) lagSamples * shape.step else 0.0
        val reach = lagReach + (if (shape.flat) shape.flatReach * shape.step else 0.0)
        if (reach > 0) from = back(from, reach)
        return from
    }

    /** The point [reach] (arc length) and three more points before point [i]. */
    private fun back(i: Int, reach: Double): Int {
        var at = max(0, i - 3)
        var back = 0.0
        while (at > 0 && back < reach) {
            back += dist(samples[at].x - samples[at - 1].x, samples[at].y - samples[at - 1].y)
            at--
        }
        return at
    }

    /**
     * The overlay's ink from point [from] to [to] (exclusive) as (x, y,
     * radius) triples of consecutive smoothed points: each consecutive pair
     * is drawn as the hull of its two circles; one triple is a dot.
     */
    fun segments(from: Int, to: Int): DoubleArray {
        val r = pointRadii()
        flatStart = shape.flat
        flatEnd = shape.flat
        cuts = emptyList()
        sweeps = emptyList()
        if (to - from == 1) {
            val s = samples[from]
            val whole = from == 0 && to == samples.size
            val last = lifted && to == samples.size
            val radius = if (whole) {
                max(r[from], trimmedRadius)
            } else {
                r[from] * Taper.factor(arc[from], shape.taperStart) * (if (last && endTaper > 0) Taper.MIN_FACTOR else 1.0)
            }
            return doubleArrayOf(s.x, s.y, radius)
        }
        val step = shape.step
        val reach = (shape.kernelK + shape.fit + shape.cornerK + 4) * step
        var start = from
        var back = 0.0
        while (start > 0 && back < reach) {
            back += dist(samples[start].x - samples[start - 1].x, samples[start].y - samples[start - 1].y)
            start--
        }
        val shaper: WetShaper
        // Arc length from the start of the window's first resampled point
        // and of its second (the others follow a step apart), for the tapers.
        var arc0 = 0.0
        var arc1 = step
        if (start == 0) {
            shaper = WetShaper(shape, 0, false, null)
        } else {
            val a = splineArc(start, step)
            val phase = ceil(a / step) * step - a
            shaper = WetShaper(shape, 1, true, phase)
            arc0 = a
            arc1 = a + (if (phase > 1e-9) phase else step)
        }
        for (i in max(0, start - 1) until to) shaper.add(samples[i].x, samples[i].y, r[i])
        val ended = lifted && to == samples.size
        shaper.update(ended)
        // A whole line shorter than half its width is a dot (`StrokeOutline.isDot`).
        if (start == 0 && to == samples.size && shaper.isDot()) {
            var radius = trimmedRadius
            for (q in samples) radius = max(radius, radiusAt(q.pressure))
            return doubleArrayOf(samples[0].x, samples[0].y, radius)
        }
        var skip = 0.0
        for (i in start + 1..from) {
            skip += dist(samples[i].x - samples[i - 1].x, samples[i].y - samples[i - 1].y)
        }
        val first = max(0, floor(skip / step).toInt() - 1)
        // Stabiliser on: as far as Flutter's live ink reaches (its final
        // line, round ends a sample short: shownOf); until the pen-down
        // hook is decided, its first point.
        val n = when {
            shape.lag == 0 || ended -> shaper.length
            this.start < 0 -> min(1, shaper.length)
            else -> shownOf(min(shaper.length, max(1, shaper.finalCount)), shaper.length)
        }
        if (n == 0) return DoubleArray(0)
        val rr = tapered(shaper, arc0, arc1, ended)
        if (n - first < 2) {
            val i = min(first, n - 1)
            return doubleArrayOf(shaper.cx[i], shaper.cy[i], rr[i])
        }
        flatStart = shape.flat && start == 0 && first == 0
        if (shape.flat) {
            val ends = WetInkEnds.of(shaper.cx, shaper.cy, rr, shaper.corners, n, first, step, start == 0, shape.flatReach)
            cuts = ends.cuts.map { WetCut(it.piece - first, it.px, it.py, it.nx, it.ny, it.atStart) }
            sweeps = ends.sweeps.map { WetSweep(it.piece - first, it.a, it.b, it.atStart) }
        }
        val out = DoubleArray((n - first) * 3)
        for (i in first until n) {
            val o = (i - first) * 3
            out[o] = shaper.cx[i]
            out[o + 1] = shaper.cy[i]
            out[o + 2] = rr[i]
        }
        return out
    }

    /**
     * The radii of [shaper]'s points with the tapers: the start's by arc
     * length from the start (the first point at [arc0], the second at
     * [arc1], then a step apart), once [ended] and committed the end's.
     */
    private fun tapered(shaper: WetShaper, arc0: Double, arc1: Double, ended: Boolean): DoubleArray {
        val n = shaper.length
        val step = shape.step
        val r = DoubleArray(n) { shaper.rr[it] }
        fun arcOf(i: Int) = if (i == 0) arc0 else arc1 + (i - 1) * step
        if (shape.taperStart > 0) {
            for (i in 0 until n) r[i] *= Taper.factor(arcOf(i), shape.taperStart)
        }
        if (ended && endTaper > 0 && n > 1 && samples.size > 1) {
            val total = splineArc(samples.size - 1, step)
            val length = min(endTaper, total * Taper.MAX_END_SHARE)
            for (i in n - 1 downTo 0) {
                val along = if (i == n - 1) 0.0 else total - arcOf(i)
                if (along >= length) break
                r[i] *= Taper.factor(along, length)
            }
        }
        return r
    }

    // Spline length from the first point to point i (as the outline's
    // resampling measures it), for the points so far.
    private val arcs = DoubleList().apply { add(0.0) }

    private fun splineArc(i: Int, step: Double): Double {
        while (arcs.size <= i) {
            val k = arcs.size - 1
            val a = samples[k]
            val b = samples[k + 1]
            val bx: Double
            val by: Double
            if (k > 0) {
                bx = samples[k - 1].x
                by = samples[k - 1].y
            } else {
                bx = 2 * a.x - b.x
                by = 2 * a.y - b.y
            }
            val ax: Double
            val ay: Double
            if (k + 2 < samples.size) {
                ax = samples[k + 2].x
                ay = samples[k + 2].y
            } else {
                ax = 2 * b.x - a.x
                ay = 2 * b.y - a.y
            }
            arcs.add(arcs[k] + WetShaper.segmentLength(bx, by, a.x, a.y, b.x, b.y, ax, ay, step))
        }
        return arcs[i]
    }

    /** The first of the [n] points to keep (the pen-down hook removed), or -1 while undecided; `HookFinder.startCut`. */
    private fun startCut(n: Int, ended: Boolean): Int {
        if (shape.hookStart <= 0) return 0
        val at = { i: Int -> i }
        val arc = hookArcs(n, at, shape.hookStart + shape.hookBody)
            ?: if (ended) hookArcs(n, at, Double.POSITIVE_INFINITY)!! else return -1
        return hookCut(arc, at, shape.hookStart)
    }

    /** How many of the [n] points to keep at pen-up (the pen-up hook removed); `HookFinder.endKeep`. */
    private fun endKeep(n: Int): Int {
        if (shape.hookEnd <= 0) return n
        val at = { i: Int -> n - 1 - i }
        val arc = hookArcs(n, at, shape.hookEnd + shape.hookBody) ?: hookArcs(n, at, Double.POSITIVE_INFINITY)!!
        val cut = hookCut(arc, at, shape.hookEnd)
        if (cut == 0) return n
        var total = 0.0
        for (i in 1 until n) total += dist(allX[i] - allX[i - 1], allY[i] - allY[i - 1])
        if (total - arc[cut] < 2 * arc[cut]) return n
        return n - cut
    }

    /** Arc lengths from the end mapped by [at] up to [length] and one point beyond, or null when the points do not reach. */
    private fun hookArcs(n: Int, at: (Int) -> Int, length: Double): DoubleList? {
        val arc = DoubleList().apply { add(0.0) }
        var beyond = -1
        for (i in 1 until n) {
            arc.add(arc[i - 1] + dist(allX[at(i)] - allX[at(i - 1)], allY[at(i)] - allY[at(i - 1)]))
            if (beyond < 0 && arc[i] >= length) beyond = i
            if (beyond >= 0 && i > beyond) return arc
        }
        return if (length.isFinite()) null else arc
    }

    /** The furthest kink within [maxHook] of the end mapped by [at], as a count of points to drop. */
    private fun hookCut(arc: DoubleList, at: (Int) -> Int, maxHook: Double): Int {
        var cut = 0
        val m = arc.size
        var j = 1
        while (j < m && arc[j] <= maxHook) {
            var b = j + 2
            while (b < m && arc[b] - arc[j] < shape.hookBody) b++
            if (b >= m) break
            var l = max(0, j - 2)
            while (l > 0 && arc[j] - arc[l] < shape.hookLocal) l--
            val jx = allX[at(j)]
            val jy = allY[at(j)]
            val hx = jx - allX[at(0)]
            val hy = jy - allY[at(0)]
            val bx = allX[at(b)] - jx
            val by = allY[at(b)] - jy
            val lx = jx - allX[at(l)]
            val ly = jy - allY[at(l)]
            val turn = angle(hx, hy, bx, by)
            val localTurn = angle(lx, ly, bx, by)
            if (turn > HOOK_TURN && localTurn > HOOK_LOCAL_TURN && localTurn >= HOOK_LOCAL_SHARE * turn) cut = j
            j++
        }
        return cut
    }

    companion object {
        /** `WetInkModel.endFrames`: frames the tail stays after `end`. */
        const val END_FRAMES = 3

        // `HookFinder`'s turns.
        private val HOOK_TURN = Math.toRadians(40.0)
        private val HOOK_LOCAL_TURN = Math.toRadians(30.0)
        private const val HOOK_LOCAL_SHARE = 0.85

        fun angle(ax: Double, ay: Double, bx: Double, by: Double) = abs(atan2(ax * by - ay * bx, ax * bx + ay * by))

        fun dist(dx: Double, dy: Double) = sqrt(dx * dx + dy * dy)

        private fun distanceToSegment(px: Double, py: Double, ax: Double, ay: Double, bx: Double, by: Double): Double {
            val abx = bx - ax
            val aby = by - ay
            val l2 = abx * abx + aby * aby
            if (l2 == 0.0) return dist(px - ax, py - ay)
            val t = (((px - ax) * abx + (py - ay) * aby) / l2).coerceIn(0.0, 1.0)
            return dist(px - (ax + abx * t), py - (ay + aby * t))
        }
    }
}

/**
 * The position rules of Dart's `StrokeShaper` (resampling along a
 * centripetal Catmull-Rom spline, corners, the low-pass kernel with its end
 * fit) for a piece of a line, computed in one go. Radii are interpolated,
 * not smoothed (the model has done that). With [leadIn], input sample
 * `start − 1` is only the spline's neighbour of the first segment; [phase]
 * is the arc length of the first resampled point after the start.
 */
class WetShaper(
    private val p: WetInkShape,
    private val start: Int,
    private val leadIn: Boolean,
    private val phase: Double?,
) {
    private val sx = DoubleList()
    private val sy = DoubleList()
    private val sr = DoubleList()
    private val rx = DoubleList()
    private val ry = DoubleList()
    val rr = DoubleList()
    val cx = DoubleList()
    val cy = DoubleList()
    var length = 0
        private set

    /**
     * Samples whose position and radius are final as the outline's shaper
     * decides it incrementally (`StrokeShaper.finalCount`, with the base's
     * end rules: [WetInkShape.lag], [WetInkShape.startReach]).
     */
    var finalCount = 0
        private set

    /** Corner sample indices of the last [update] (`StrokeShaper.corners`). */
    var corners = IntArray(0)
        private set

    // Resampled samples from final segments (`StrokeShaper._resFinal`) and
    // the corner scan over them: where it stopped, and the run of sharp
    // turns it is in (its best sample, -1: none).
    private var resFinal = 0
    private var scan = 0
    private var runBest = -1

    /** Whether the line is shorter than half its largest radius (`StrokeOutline.isDot`). */
    fun isDot(): Boolean {
        if (length < 2) return true
        var maxR = 0.0
        for (i in 0 until length) maxR = max(maxR, rr[i])
        return p.step * (length - 1) < maxR * 0.5
    }

    fun add(x: Double, y: Double, radius: Double) {
        val n = sx.size
        if (n > 0) {
            val dx = x - sx[n - 1]
            val dy = y - sy[n - 1]
            if (dx * dx + dy * dy < p.dedupe * p.dedupe) {
                sr[n - 1] = max(sr[n - 1], radius)
                return
            }
        }
        sx.add(x)
        sy.add(y)
        sr.add(radius)
    }

    fun update(ended: Boolean = false) {
        val n = sx.size
        if (n <= start) {
            length = 0
            finalCount = 0
            corners = IntArray(0)
            return
        }
        resample(n, ended)
        val count = rx.size
        corners = findCorners(count)
        smooth(count, corners)
        length = count
        val known = if (runBest >= 0) runBest else scan
        val posFinal = max(0, min(known, resFinal) - p.kernelK - 1)
        val settled = resFinal - max(1, p.lag)
        val roDone = if (settled > max(1, p.startReach)) settled else 0
        finalCount = min(posFinal, roDone)
    }

    private fun resample(n: Int, ended: Boolean) {
        push(sx[start], sy[start], sr[start])
        resFinal = 1
        var next = if (phase != null && phase > 1e-9) phase else p.step
        for (k in start until n - 1) {
            next = segment(k, n, next)
            // Final: the sample after the segment's end is (not the last
            // input sample), and the input is still growing.
            if (k + 2 <= n - 2 && !ended) resFinal = rx.size
        }
        val along = next - p.step
        if (n - 1 > start && along < -p.step * 1e-3) push(sx[n - 1], sy[n - 1], sr[n - 1])
    }

    private fun segment(k: Int, n: Int, nextIn: Double): Double {
        var next = nextIn
        val x1 = sx[k]
        val y1 = sy[k]
        val x2 = sx[k + 1]
        val y2 = sy[k + 1]
        val lead = k > start || (leadIn && k > 0)
        val x0 = if (lead) sx[k - 1] else 2 * x1 - x2
        val y0 = if (lead) sy[k - 1] else 2 * y1 - y2
        val x3 = if (k + 2 < n) sx[k + 2] else 2 * x2 - x1
        val y3 = if (k + 2 < n) sy[k + 2] else 2 * y2 - y1
        val r1 = sr[k]
        val r2 = sr[k + 1]
        val gap = WetInkModel.dist(x2 - x1, y2 - y1)
        val pieces = max(1, min(64, ceil(gap / (p.step * 0.5)).toInt()))
        val cr = CatmullRom(x0, y0, x1, y1, x2, y2, x3, y3)
        var ax = x1
        var ay = y1
        var along = 0.0
        for (q in 1..pieces) {
            val t = q.toDouble() / pieces
            val bx: Double
            val by: Double
            if (q == pieces) {
                bx = x2
                by = y2
            } else {
                cr.at(t)
                bx = cr.outX
                by = cr.outY
            }
            val len = WetInkModel.dist(bx - ax, by - ay)
            while (next <= along + len && len > 0) {
                val u = (next - along) / len
                val tt = (q - 1 + u) / pieces
                push(ax + (bx - ax) * u, ay + (by - ay) * u, r1 + (r2 - r1) * tt)
                next += p.step
            }
            along += len
            ax = bx
            ay = by
        }
        return next - along
    }

    private fun push(x: Double, y: Double, r: Double) {
        rx.add(x)
        ry.add(y)
        rr.add(r)
    }

    private fun turnAt(i: Int): Double {
        val k = p.cornerK
        val ax = rx[i] - rx[i - k]
        val ay = ry[i] - ry[i - k]
        val bx = rx[i + k] - rx[i]
        val by = ry[i + k] - ry[i]
        return WetInkModel.angle(ax, ay, bx, by)
    }

    /** How far sample [i] lies along the direction the line came in from before the run starting at [first] (`StrokeShaper._tipScore`). */
    private fun tipScore(first: Int, i: Int): Double {
        val k = p.cornerK
        val ux = rx[first] - rx[first - k]
        val uy = ry[first] - ry[first - k]
        return (rx[i] - rx[first]) * ux + (ry[i] - ry[first]) * uy
    }

    private fun findCorners(count: Int): IntArray {
        val k = p.cornerK
        val found = ArrayList<Int>()
        var first = -1
        var best = -1
        var score = 0.0
        var i = k
        scan = -1
        while (i + k < count) {
            // Where the outline's scan of final samples stops, and its run.
            if (scan < 0 && i + k >= resFinal) {
                scan = i
                runBest = best
            }
            if (turnAt(i) > MIN_TURN) {
                if (first < 0) {
                    first = i
                    best = i
                    score = 0.0
                } else if (tipScore(first, i) > score) {
                    best = i
                    score = tipScore(first, i)
                }
            } else if (first >= 0) {
                found.add(best)
                first = -1
                best = -1
                score = 0.0
            }
            i++
        }
        if (scan < 0) {
            scan = i
            runBest = best
        }
        if (best >= 0) found.add(best)
        return found.toIntArray()
    }

    private fun smooth(count: Int, corners: IntArray) {
        cx.size = count
        cy.size = count
        val bounds = IntArray(corners.size + 2)
        bounds[0] = 0
        for (c in corners.indices) bounds[c + 1] = corners[c]
        bounds[bounds.size - 1] = count - 1
        var b = 1
        for (i in 0 until count) {
            while (bounds[b] < i) b++
            val lo = bounds[b - 1]
            val hi = bounds[b]
            cx[i] = filtered(rx, i, lo, hi)
            cy[i] = filtered(ry, i, lo, hi)
        }
    }

    private fun filtered(v: DoubleList, i: Int, lo: Int, hi: Int): Double {
        if (i == lo || i == hi || hi - lo < 2) return v[i]
        val w = p.kernel
        val k = p.kernelK
        // A stretch shorter than the fit is held at its ends (StrokeShaper).
        val fit = if (hi - lo >= p.fit) p.fit else 0
        var sum = 0.0
        for (m in max(lo, i - k)..min(hi, i + k)) sum += w[m - i + k] * v[m]
        if (i - k < lo) {
            val (a, c) = endFit(v, lo, 1, fit)
            for (m in i - k until lo) {
                val j = (lo - m).toDouble()
                sum += w[m - i + k] * (v[lo] + a * j + c * j * j)
            }
        }
        if (i + k > hi) {
            val (a, c) = endFit(v, hi, -1, fit)
            for (m in hi + 1..i + k) {
                val j = (m - hi).toDouble()
                sum += w[m - i + k] * (v[hi] + a * j + c * j * j)
            }
        }
        return sum
    }

    companion object {
        private val MIN_TURN = Math.toRadians(100.0)

        /** `LineFilters.endFit`. */
        fun endFit(v: DoubleList, end: Int, inward: Int, fit: Int): Pair<Double, Double> {
            val origin = v[end]
            var s2 = 0.0
            var s3 = 0.0
            var s4 = 0.0
            var t1 = 0.0
            var t2 = 0.0
            for (j in 1..fit) {
                val k = -j.toDouble()
                val d = v[end + inward * j] - origin
                s2 += k * k
                s3 += k * k * k
                s4 += k * k * k * k
                t1 += k * d
                t2 += k * k * d
            }
            if (fit == 0) return Pair(0.0, 0.0)
            if (fit < 3) return Pair(t1 / s2, 0.0)
            val det = s2 * s4 - s3 * s3
            if (abs(det) < 1e-12) return Pair(t1 / s2, 0.0)
            return Pair((t1 * s4 - t2 * s3) / det, (s2 * t2 - s3 * t1) / det)
        }

        /** `StrokeShaper.segmentLength`. */
        fun segmentLength(
            x0: Double, y0: Double, x1: Double, y1: Double,
            x2: Double, y2: Double, x3: Double, y3: Double, step: Double,
        ): Double {
            val gap = WetInkModel.dist(x2 - x1, y2 - y1)
            val pieces = max(1, min(64, ceil(gap / (step * 0.5)).toInt()))
            val cr = CatmullRom(x0, y0, x1, y1, x2, y2, x3, y3)
            var ax = x1
            var ay = y1
            var along = 0.0
            for (q in 1..pieces) {
                val bx: Double
                val by: Double
                if (q == pieces) {
                    bx = x2
                    by = y2
                } else {
                    cr.at(q.toDouble() / pieces)
                    bx = cr.outX
                    by = cr.outY
                }
                along += WetInkModel.dist(bx - ax, by - ay)
                ax = bx
                ay = by
            }
            return along
        }
    }
}

/** One centripetal Catmull-Rom segment from P1 to P2 (Barry–Goldman form). */
private class CatmullRom(
    val x0: Double, val y0: Double, val x1: Double, val y1: Double,
    val x2: Double, val y2: Double, val x3: Double, val y3: Double,
) {
    private val t1 = knot(0.0, x0, y0, x1, y1)
    private val t2 = knot(t1, x1, y1, x2, y2)
    private val t3 = knot(t2, x2, y2, x3, y3)
    var outX = 0.0
        private set
    var outY = 0.0
        private set

    private fun knot(t: Double, ax: Double, ay: Double, bx: Double, by: Double): Double {
        val d = sqrt(sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)))
        return t + max(d, 1e-6)
    }

    private fun lerp(t: Double, a: Double, b: Double, ta: Double, tb: Double) =
        (tb - t) / (tb - ta) * a + (t - ta) / (tb - ta) * b

    fun at(u: Double) {
        val t = t1 + (t2 - t1) * u
        val a1x = lerp(t, x0, x1, 0.0, t1)
        val a1y = lerp(t, y0, y1, 0.0, t1)
        val a2x = lerp(t, x1, x2, t1, t2)
        val a2y = lerp(t, y1, y2, t1, t2)
        val a3x = lerp(t, x2, x3, t2, t3)
        val a3y = lerp(t, y2, y3, t2, t3)
        val b1x = lerp(t, a1x, a2x, 0.0, t2)
        val b1y = lerp(t, a1y, a2y, 0.0, t2)
        val b2x = lerp(t, a2x, a3x, t1, t3)
        val b2y = lerp(t, a2y, a3y, t1, t3)
        outX = lerp(t, b1x, b2x, t1, t2)
        outY = lerp(t, b1y, b2y, t1, t2)
    }
}

/** A growable list of doubles (no boxing). */
class DoubleList {
    private var data = DoubleArray(64)
    var size = 0
        set(value) {
            if (value > data.size) data = data.copyOf(max(value, data.size * 2))
            for (i in field until value) data[i] = 0.0
            field = value
        }

    fun add(v: Double) {
        if (size == data.size) data = data.copyOf(data.size * 2)
        data[size++] = v
    }

    operator fun get(i: Int): Double {
        if (i >= size) throw IndexOutOfBoundsException("$i of $size")
        return data[i]
    }

    operator fun set(i: Int, v: Double) {
        if (i >= size) throw IndexOutOfBoundsException("$i of $size")
        data[i] = v
    }

    fun toArray(n: Int = size): DoubleArray = data.copyOf(n)
}

/** Dart's `Taper`: the shape of a tapered end. */
object Taper {
    const val MIN_FACTOR = 0.03
    const val MAX_END_SHARE = 0.5

    /** The radius scale [along] (≥ 0) from the end of a taper [length] long. */
    fun factor(along: Double, length: Double): Double {
        if (length <= 0 || along >= length) return 1.0
        val t = along / length
        return max(MIN_FACTOR, t * (2 - t))
    }
}
