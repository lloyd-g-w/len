package dev.len.len

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

// The overlay's flat ends (no Android types): a line-for-line port of
// `lib/ink/lab/wet_ink_ends.dart`, which the Ink Lab measures, plus the
// polygons of pieces cut off at them and of flat nib sweeps (a port of
// `emitSweep` in `lib/ink/render/flat_ends.dart`), which `WetInkLayer`
// draws.

/**
 * Piece [piece] (the hull of points `piece` and `piece + 1`) is not drawn
 * beyond the line through ([px], [py]) on the side its normal ([nx], [ny])
 * faces; [atStart]: the stroke's start's cut, else the drawn end's.
 */
class WetCut(
    val piece: Int,
    val px: Double,
    val py: Double,
    val nx: Double,
    val ny: Double,
    val atStart: Boolean,
)

/**
 * Part of piece [piece], which is drawn as flat nib sweeps instead of the
 * hull of its circles: from cross-section [a] to [b] (centre, left and
 * right end: cx, cy, lx, ly, rx, ry); [atStart]: in the start's zone.
 */
class WetSweep(val piece: Int, val a: DoubleArray, val b: DoubleArray, val atStart: Boolean)

/** The cuts and sweeps of a line's flat ends, in piece order. */
class WetEnds(val cuts: List<WetCut>, val sweeps: List<WetSweep>)

/**
 * The flat ends of the overlay's line, as Flutter's ink draws them
 * (`FlatEnds`): at the stroke's start and at the end, also the moving pen
 * tip (Flutter draws a live stroke's tip as its committed end). Within an
 * end's zone (the points whose circles touch the end's) each piece is a
 * flat nib's sweep between its cross-sections, and the zone's last
 * stretch running the end's way is cut off at the butt cap's line, square
 * to where the line runs over its last half radius. See the Dart model's
 * documentation.
 */
object WetInkEnds {
    /**
     * The cuts and sweeps of the line of [n] points ([x], [y], radii [r],
     * [corners]) whose pieces from point [first] on are drawn: at its start
     * if [start] (point 0 is the stroke's start), and at its end; a zone
     * reaches at most [reach] points.
     */
    fun of(
        x: DoubleList,
        y: DoubleList,
        r: DoubleArray,
        corners: IntArray,
        n: Int,
        first: Int,
        step: Double,
        start: Boolean,
        reach: Int,
    ): WetEnds {
        val e = n - 1
        val inner = corners.filter { it > 0 && it < e }
        val bounds = IntArray(inner.size + 2)
        for (c in inner.indices) bounds[c + 1] = inner[c]
        bounds[bounds.size - 1] = e

        fun frameAt(i: Int, lo: Int, hi: Int) = frame(x, y, r, i, lo, hi, step, (i == 0 && start) || i == e)

        fun cap(i: Int, lo: Int, hi: Int, back: Boolean, atStart: Boolean, piece: Int): WetCut {
            val f = frameAt(i, lo, hi)
            val along = -r[i] * f[2]
            val sign = if (back) -1.0 else 1.0
            return WetCut(piece, x[i] + along * f[0], y[i] + along * f[1], sign * f[0], sign * f[1], atStart)
        }

        // The offset points at i, as `RibbonEmitter._offsets`.
        fun section(i: Int, lo: Int, hi: Int): DoubleArray {
            val f = frameAt(i, lo, hi)
            val along = -r[i] * f[2]
            val across = r[i] * sqrt(1 - f[2] * f[2])
            val ox = x[i] + along * f[0]
            val oy = y[i] + along * f[1]
            return doubleArrayOf(x[i], y[i], ox - across * f[1], oy + across * f[0], ox + across * f[1], oy - across * f[0])
        }

        fun touches(k: Int, end: Int): Boolean {
            val dx = x[k] - x[end]
            val dy = y[k] - y[end]
            val d = r[k] + r[end]
            return dx * dx + dy * dy <= d * d
        }

        // The zones (`FlatEnds.of`): the start's, points 0..to (0..clipTo
        // cut off), and the end's, from..e (clipFrom..e). A whole line of
        // fewer than four points is one run between its butt caps.
        val startLine = if (start) cap(0, 0, bounds[1], true, true, 0) else null
        val endLine = cap(e, bounds[bounds.size - 2], e, false, false, e - 1)
        var to = 0
        var clipTo = 0
        var from = e
        var clipFrom = e
        if (start && n < 4) {
            from = 0
        } else {
            if (startLine != null) {
                val most = min(e / 2, reach)
                while (to < most && touches(to + 1, 0)) to++
                while (clipTo < to && along(x, y, clipTo, clipTo + 1, -startLine.nx, -startLine.ny)) clipTo++
            }
            val most = if (start) min(e - e / 2, reach) else reach
            while (e - from < most && from > 0 && touches(from - 1, e)) from--
            while (clipFrom > from && along(x, y, clipFrom - 1, clipFrom, endLine.nx, endLine.ny)) clipFrom--
        }

        val cuts = ArrayList<WetCut>()
        val sweeps = ArrayList<WetSweep>()
        var b = 1
        for (j in first until e) {
            while (bounds[b] <= j) b++
            val lo = bounds[b - 1]
            val hi = bounds[b]
            val inStart = startLine != null && j + 1 <= to
            val inEnd = j >= from
            // A corner in a zone: the nib turns on it.
            if (inEnd && j == lo && lo > 0) sweeps.add(WetSweep(j, section(lo, bounds[b - 2], lo), section(lo, lo, hi), inStart))
            if (inStart || inEnd) sweeps.add(WetSweep(j, section(j, lo, hi), section(j + 1, lo, hi), inStart))
            if (inStart && j + 1 == hi && hi < e && hi < from) {
                sweeps.add(WetSweep(j, section(hi, lo, hi), section(hi, hi, bounds[b + 1]), true))
            }
            // A hull's round end at the line's ends goes too.
            val hull = !inStart && !inEnd
            if (startLine != null && (j + 1 <= clipTo || (j == 0 && hull))) {
                cuts.add(WetCut(j, startLine.px, startLine.py, startLine.nx, startLine.ny, true))
            }
            if (j >= clipFrom || (j == e - 1 && hull)) cuts.add(WetCut(j, endLine.px, endLine.py, endLine.nx, endLine.ny, false))
        }
        return WetEnds(cuts, sweeps)
    }

    /** `RibbonEmitter._frame`: unit tangent and radius slope at point [i] of the stretch [lo]..[hi]; at an [end] as a flat cap has it. */
    private fun frame(
        x: DoubleList,
        y: DoubleList,
        r: DoubleArray,
        i: Int,
        lo: Int,
        hi: Int,
        step: Double,
        end: Boolean,
    ): DoubleArray {
        var a = max(lo, i - 1)
        var c = min(hi, i + 1)
        if (end && hi - lo >= 3) {
            val k = max(1, ceil(0.5 * r[i] / step).toInt())
            if (i == 0) {
                a = 1
                c = min(hi - 1, 1 + k)
            } else {
                a = max(lo + 1, i - 1 - k)
                c = i - 1
            }
        }
        var dx = x[c] - x[a]
        var dy = y[c] - y[a]
        var d = sqrt(dx * dx + dy * dy)
        if (d < 1e-9 && (a > lo || c < hi)) {
            a = max(lo, a - 1)
            c = min(hi, c + 1)
            dx = x[c] - x[a]
            dy = y[c] - y[a]
            d = sqrt(dx * dx + dy * dy)
        }
        if (d < 1e-9) return doubleArrayOf(1.0, 0.0, 0.0)
        val slope = ((r[c] - r[a]) / d).coerceIn(-0.9, 0.9)
        return doubleArrayOf(dx / d, dy / d, slope)
    }

    private fun along(x: DoubleList, y: DoubleList, a: Int, b: Int, tx: Double, ty: Double): Boolean {
        val dx = x[b] - x[a]
        val dy = y[b] - y[a]
        val d = sqrt(dx * dx + dy * dy)
        return d < 1e-9 || (dx * tx + dy * ty) >= 0.5 * d
    }

    /**
     * The hull of the circles (a, ra) and (b, rb) cut off at the lines
     * (px, py, nx, ny) in [cuts] (4 values each), as a polygon (x, y
     * pairs) wound clockwise on screen (y down), its arcs within
     * [tolerance] of the circles; empty when nothing is left.
     */
    fun cutHull(
        ax: Float,
        ay: Float,
        ra: Float,
        bx: Float,
        by: Float,
        rb: Float,
        cuts: FloatArray,
        tolerance: Float,
    ): FloatArray {
        val dx = (bx - ax).toDouble()
        val dy = (by - ay).toDouble()
        val len = sqrt(dx * dx + dy * dy)
        val pts = ArrayList<Double>()
        fun arc(cx: Float, cy: Float, r: Float, from: Double, sweep: Double) {
            val perStep = if (r <= tolerance) PI / 2 else 2 * acos(1 - tolerance / r.toDouble())
            val steps = max(1, min(64, ceil(sweep / perStep).toInt()))
            for (k in 0..steps) {
                val t = from + sweep * k / steps
                pts.add(cx + r * cos(t))
                pts.add(cy + r * sin(t))
            }
        }
        if (len <= Math.abs(ra - rb)) {
            if (ra >= rb) arc(ax, ay, ra, 0.0, 2 * PI) else arc(bx, by, rb, 0.0, 2 * PI)
        } else {
            // The tangents touch at ±(π/2 + asin((rb − ra) / len)) from the direction.
            val angle = atan2(dy, dx)
            val t = PI / 2 + asin(((rb - ra) / len).coerceIn(-1.0, 1.0))
            arc(bx, by, rb, angle - t, 2 * t)
            arc(ax, ay, ra, angle + t, 2 * PI - 2 * t)
        }
        return cut(pts.toDoubleArray(), cuts)
    }

    /**
     * The area a flat nib sweeps from cross-section [a] to [b] (cx, cy, lx,
     * ly, rx, ry; `emitSweep`, which Flutter's flat ends draw) cut off at
     * the lines in [cuts] (as [cutHull]'s), as polygons wound as
     * [cutHull]'s, the nib's ends' arcs within [tolerance] of their chords.
     */
    fun cutSweep(a: DoubleArray, b: DoubleArray, cuts: FloatArray, tolerance: Float): List<FloatArray> {
        val la = atan2(a[3] - a[1], a[2] - a[0])
        val lb = atan2(b[3] - b[1], b[2] - b[0])
        val ra = atan2(a[5] - a[1], a[4] - a[0])
        val rb = atan2(b[5] - b[1], b[4] - b[0])
        val dl = wrap(lb - la)
        val dr = wrap(rb - ra)
        val mla = hypot(a[2] - a[0], a[3] - a[1])
        val mlb = hypot(b[2] - b[0], b[3] - b[1])
        val mra = hypot(a[4] - a[0], a[5] - a[1])
        val mrb = hypot(b[4] - b[0], b[5] - b[1])
        val reach = maxOf(mla, mlb, mra, mrb)
        val perStep = if (reach <= tolerance) PI else sqrt(8 * tolerance / reach)
        val steps = max(1, min(64, ceil(max(abs(dl), abs(dr)) / perStep).toInt()))
        fun at(t: Double): DoubleArray {
            if (t == 0.0) return a
            if (t == 1.0) return b
            val cx = a[0] + (b[0] - a[0]) * t
            val cy = a[1] + (b[1] - a[1]) * t
            val ml = mla * (1 - t) + mlb * t
            val mr = mra * (1 - t) + mrb * t
            val al = la + dl * t
            val ar = ra + dr * t
            return doubleArrayOf(cx, cy, cx + ml * cos(al), cy + ml * sin(al), cx + mr * cos(ar), cy + mr * sin(ar))
        }
        val out = ArrayList<FloatArray>()
        fun add(poly: DoubleArray) {
            var area = 0.0
            val m = poly.size / 2
            for (i in 0 until m) {
                val j = (i + 1) % m
                area += poly[2 * i] * poly[2 * j + 1] - poly[2 * j] * poly[2 * i + 1]
            }
            if (abs(area) < 1e-12) return
            val wound = if (area > 0) poly else DoubleArray(poly.size) { poly[2 * (m - 1 - it / 2) + it % 2] }
            val p = cut(wound, cuts)
            if (p.isNotEmpty()) out.add(p)
        }
        var s = a
        for (k in 1..steps) {
            val t = at(k.toDouble() / steps)
            // Two triangles meeting where the sections cross (the nib turned
            // about a point on it), else the hull of both.
            val x = cross(s[2], s[3], s[4], s[5], t[2], t[3], t[4], t[5])
            if (x != null) {
                add(doubleArrayOf(s[2], s[3], t[2], t[3], x[0], x[1]))
                add(doubleArrayOf(s[4], s[5], t[4], t[5], x[0], x[1]))
            } else {
                add(hull(doubleArrayOf(s[2], s[3], s[4], s[5], t[2], t[3], t[4], t[5])))
            }
            s = t
        }
        return out
    }

    private fun wrap(angle: Double): Double {
        var a = angle
        while (a > PI) a -= 2 * PI
        while (a <= -PI) a += 2 * PI
        return a
    }

    /** Where segments A and B cross (strictly inside both), or null. */
    private fun cross(
        ax: Double,
        ay: Double,
        bx: Double,
        by: Double,
        cx: Double,
        cy: Double,
        dx: Double,
        dy: Double,
    ): DoubleArray? {
        val ux = bx - ax
        val uy = by - ay
        val vx = dx - cx
        val vy = dy - cy
        val den = ux * vy - uy * vx
        if (abs(den) < 1e-12) return null
        val t = ((cx - ax) * vy - (cy - ay) * vx) / den
        val s = ((cx - ax) * uy - (cy - ay) * ux) / den
        if (t <= 0 || t >= 1 || s <= 0 || s >= 1) return null
        return doubleArrayOf(ax + ux * t, ay + uy * t)
    }

    /** The convex hull of the points (x0, y0, x1, y1, …), as a polygon. */
    private fun hull(p: DoubleArray): DoubleArray {
        val n = p.size / 2
        val order = (0 until n).sortedWith(compareBy<Int>({ p[2 * it] }, { p[2 * it + 1] }))
        fun turn(o: Int, a: Int, b: Int) =
            (p[2 * a] - p[2 * o]) * (p[2 * b + 1] - p[2 * o + 1]) - (p[2 * a + 1] - p[2 * o + 1]) * (p[2 * b] - p[2 * o])
        val h = ArrayList<Int>()
        for (pass in listOf(order, order.reversed())) {
            val start = h.size
            for (i in pass) {
                while (h.size >= start + 2 && turn(h[h.size - 2], h[h.size - 1], i) <= 0) h.removeAt(h.size - 1)
                h.add(i)
            }
            h.removeAt(h.size - 1)
        }
        return DoubleArray(h.size * 2) { p[2 * h[it / 2] + it % 2] }
    }

    /** [polygon] cut off at the lines in [cuts] (as [cutHull]'s); empty when nothing is left. */
    private fun cut(polygon: DoubleArray, cuts: FloatArray): FloatArray {
        var poly = polygon
        for (c in 0 until cuts.size / 4) {
            val px = cuts[4 * c].toDouble()
            val py = cuts[4 * c + 1].toDouble()
            val nx = cuts[4 * c + 2].toDouble()
            val ny = cuts[4 * c + 3].toDouble()
            val m = poly.size / 2
            val next = ArrayList<Double>()
            for (i in 0 until m) {
                val p = (i + m - 1) % m
                val sa = (poly[2 * p] - px) * nx + (poly[2 * p + 1] - py) * ny
                val sp = (poly[2 * i] - px) * nx + (poly[2 * i + 1] - py) * ny
                if ((sa <= 0) != (sp <= 0)) {
                    val u = sa / (sa - sp)
                    next.add(poly[2 * p] + (poly[2 * i] - poly[2 * p]) * u)
                    next.add(poly[2 * p + 1] + (poly[2 * i + 1] - poly[2 * p + 1]) * u)
                }
                if (sp <= 0) {
                    next.add(poly[2 * i])
                    next.add(poly[2 * i + 1])
                }
            }
            poly = next.toDoubleArray()
            if (poly.size < 6) return FloatArray(0)
        }
        return FloatArray(poly.size) { poly[it].toFloat() }
    }
}
