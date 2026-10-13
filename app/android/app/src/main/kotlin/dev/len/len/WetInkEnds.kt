package dev.len.len

import kotlin.math.PI
import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

// The overlay's flat ends (no Android types): a line-for-line port of
// `lib/ink/lab/wet_ink_ends.dart`, which the Ink Lab measures, plus the
// polygon of a piece cut off at them, which `WetInkLayer` draws.

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
 * The flat ends of the overlay's line, as Flutter's ink draws them: the
 * butt cap square to where the line runs over its last half radius, and
 * the round pieces next to it cut off at the cap's line (the start always,
 * the end once Flutter has committed the stroke) or, at the pen tip, at
 * the cross-section ahead of each piece, back to a piece Flutter draws
 * round (a fold). See the Dart model's documentation.
 */
object WetInkEnds {
    /** `RibbonEmitter.foldAdvance`, `RibbonEmitter.foldCos`. */
    private const val FOLD_ADVANCE = -1.0
    private const val FOLD_COS = -0.5

    /**
     * The cuts of the line of [n] points ([x], [y], radii [r], [corners])
     * whose pieces from point [first] on are drawn: at its start if [start]
     * (the stroke's start is point 0), and at its end (the committed
     * stroke's end if [ended]); in the order of their pieces, a start's
     * before an end's.
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
        ended: Boolean,
    ): List<WetCut> {
        val e = n - 1
        val inner = corners.filter { it > 0 && it < e }
        val bounds = IntArray(inner.size + 2)
        for (c in inner.indices) bounds[c + 1] = inner[c]
        bounds[bounds.size - 1] = e

        fun section(i: Int, lo: Int, hi: Int, back: Boolean, atStart: Boolean, piece: Int): WetCut {
            val f = frame(x, y, r, i, lo, hi, step, i == 0 || i == e)
            val along = -r[i] * f[2]
            val sign = if (back) -1.0 else 1.0
            return WetCut(piece, x[i] + along * f[0], y[i] + along * f[1], sign * f[0], sign * f[1], atStart)
        }

        fun next(j: Int, l: WetCut, sign: Double) =
            along(x, y, j, j + 1, sign * l.nx, sign * l.ny) && (reaches(x, y, r, j, l) || reaches(x, y, r, j + 1, l))

        val starts = ArrayList<WetCut>()
        if (start) {
            val line = section(0, 0, bounds[1], true, true, 0)
            var j = 0
            while (j < e && (j == 0 || next(j, line, -1.0))) {
                if (j >= first) starts.add(WetCut(j, line.px, line.py, line.nx, line.ny, true))
                j++
            }
        }
        val ends = ArrayList<WetCut>()
        val line = section(e, bounds[bounds.size - 2], e, false, false, e - 1)
        var b = bounds.size - 1
        var j = e - 1
        while (j >= first && (j == e - 1 || next(j, line, 1.0))) {
            if (ended) {
                ends.add(WetCut(j, line.px, line.py, line.nx, line.ny, false))
            } else {
                while (bounds[b - 1] > j) b--
                val lo = bounds[b - 1]
                val hi = bounds[b]
                if (folded(x, y, r, j, lo, hi, e, step)) break
                ends.add(if (j + 1 == e) line else section(j + 1, lo, hi, false, false, j))
            }
            j--
        }
        // In piece order, as the Dart model lists them.
        val out = ArrayList<WetCut>(starts.size + ends.size)
        var s = 0
        var k = ends.size - 1
        while (s < starts.size || k >= 0) {
            if (k < 0 || (s < starts.size && starts[s].piece <= ends[k].piece)) out.add(starts[s++]) else out.add(ends[k--])
        }
        return out
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

    /** `RibbonEmitter._folded`: whether Flutter draws piece [i] as a round capsule. */
    private fun folded(x: DoubleList, y: DoubleList, r: DoubleArray, i: Int, lo: Int, hi: Int, e: Int, step: Double): Boolean {
        val ux = x[i + 1] - x[i]
        val uy = y[i + 1] - y[i]
        val u = sqrt(ux * ux + uy * uy)
        if (u < 1e-9) return true
        val fa = frame(x, y, r, i, lo, hi, step, i == 0)
        val fb = frame(x, y, r, i + 1, lo, hi, step, i + 1 == e)
        val aAlong = -r[i] * fa[2]
        val aAcross = r[i] * sqrt(1 - fa[2] * fa[2])
        val bAlong = -r[i + 1] * fb[2]
        val bAcross = r[i + 1] * sqrt(1 - fb[2] * fb[2])
        val least = FOLD_ADVANCE * u * u
        for (side in doubleArrayOf(1.0, -1.0)) {
            val ax = x[i] + aAlong * fa[0] - side * aAcross * fa[1]
            val ay = y[i] + aAlong * fa[1] + side * aAcross * fa[0]
            val bx = x[i + 1] + bAlong * fb[0] - side * bAcross * fb[1]
            val by = y[i + 1] + bAlong * fb[1] + side * bAcross * fb[0]
            if ((bx - ax) * ux + (by - ay) * uy < least) return true
        }
        return fa[0] * fb[0] + fa[1] * fb[1] < FOLD_COS
    }

    private fun along(x: DoubleList, y: DoubleList, a: Int, b: Int, tx: Double, ty: Double): Boolean {
        val dx = x[b] - x[a]
        val dy = y[b] - y[a]
        val d = sqrt(dx * dx + dy * dy)
        return d < 1e-9 || (dx * tx + dy * ty) >= 0.5 * d
    }

    private fun reaches(x: DoubleList, y: DoubleList, r: DoubleArray, i: Int, l: WetCut) =
        (x[i] - l.px) * l.nx + (y[i] - l.py) * l.ny > -r[i]

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
        var poly = pts.toDoubleArray()
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
