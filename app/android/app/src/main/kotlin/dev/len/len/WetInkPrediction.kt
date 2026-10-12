package dev.len.len

import kotlin.math.acos
import kotlin.math.min
import kotlin.math.sqrt

/**
 * How much of a motion prediction the low-latency overlay draws (pure
 * Kotlin, no Android types, so `WetInkPredictionTest` can replay the Ink
 * Lab recordings through it on a plain JVM; docs/INK_LAB.md, "Prediction").
 *
 * The predictor (androidx `MotionEventPredictor` on the device) extrapolates
 * the pen's recent motion. Where that motion is about to change (the pen
 * slows down, turns or lifts) the extrapolation runs past the real path and
 * the next event takes it back: a tail that flicks out and is cut off. Like
 * native note apps, the overlay therefore draws only a short, cautious
 * piece of it, as far along the predicted path as the smallest of:
 * - the points at most [horizonMs] ahead of the newest sample;
 * - [speedReach] × the distance the recent speed covers in [horizonMs] (the
 *   predictor's acceleration terms never carry it further);
 * - [maxRadii] tip radii;
 * - the length over which a straight line leaves a path curving as the pen
 *   does now by [bendRadii] tip radii;
 *
 * all scaled smoothly down to nothing as the pen slows down (speed over the
 * last [windowMs] against the one before), turns (direction over the last
 * [windowMs] against the one before) or lifts (pressure falling over the
 * last [windowMs], or low). At pen-down (less than two windows of samples)
 * nothing is drawn.
 *
 * Feed every real sample of the contact ([add]; [reset] at pen-down), then
 * [filter] the predictor's points after each event. Allocation-free.
 */
class WetInkPrediction(
    /** The furthest ahead (ms) a drawn point may be. */
    val horizonMs: Double = HORIZON_MS,
    /** The longest drawn prediction, in tip radii. */
    val maxRadii: Double = MAX_RADII,
    /** The longest drawn prediction, as a share of the distance the recent speed covers in [horizonMs]. */
    val speedReach: Double = SPEED_REACH,
    /** How far (tip radii) a straight prediction may leave a path that keeps curving as it does now. */
    val bendRadii: Double = BEND_RADII,
    /** The window (ms) over which speed, direction and pressure change are measured. */
    val windowMs: Double = WINDOW_MS,
    /** Speed over the last window / over the one before: none at or below [slowNone], full from [slowFull]. */
    val slowNone: Double = SLOW_NONE,
    val slowFull: Double = SLOW_FULL,
    /** Turn (radians) between the two windows' directions: full up to [turnFull], none from [turnNone]. */
    val turnFull: Double = TURN_FULL,
    val turnNone: Double = TURN_NONE,
    /** Normalised pressure lost over the last window: full up to [liftFull], none from [liftNone]. */
    val liftFull: Double = LIFT_FULL,
    val liftNone: Double = LIFT_NONE,
    /** Normalised pressure: none at or below [pressureNone], full from [pressureFull]. */
    val pressureNone: Double = PRESSURE_NONE,
    val pressureFull: Double = PRESSURE_FULL,
) {
    // The newest real samples (a ring, oldest overwritten).
    private val xs = DoubleArray(HISTORY)
    private val ys = DoubleArray(HISTORY)
    private val ps = DoubleArray(HISTORY)
    private val ts = DoubleArray(HISTORY)
    private var size = 0
    private var head = 0 // Index of the newest sample.

    // [sampleAt]'s answer.
    private var atX = 0.0
    private var atY = 0.0
    private var atP = 0.0

    /** Forgets the samples (a new contact). */
    fun reset() {
        size = 0
        head = 0
    }

    /** Adds a real sample: position (px), normalised pressure (0..1), time (ms). */
    fun add(x: Double, y: Double, pressure: Double, timeMs: Double) {
        head = (head + 1) % HISTORY
        xs[head] = x
        ys[head] = y
        ps[head] = pressure
        ts[head] = timeMs
        if (size < HISTORY) size++
    }

    /**
     * Writes into [out] the (x, y) pairs to draw after the newest sample,
     * taken from the [n] predicted (x, y, ms after the newest sample) triples
     * in [raw], for a tip of [radius] px; the last one may be cut short
     * between two predicted points. Returns how many pairs it wrote (at most
     * [n]; [out] must hold them).
     */
    fun filter(raw: FloatArray, n: Int, radius: Double, out: FloatArray): Int {
        if (n == 0) return 0
        val reach = reach(radius)
        if (reach < MIN_REACH_PX) return 0
        var px = xs[head]
        var py = ys[head]
        var left = reach
        var m = 0
        for (i in 0 until n) {
            if (raw[i * 3 + 2] > horizonMs) break
            val x = raw[i * 3].toDouble()
            val y = raw[i * 3 + 1].toDouble()
            val d = sqrt((x - px) * (x - px) + (y - py) * (y - py))
            if (d >= left) {
                // Ends on the way to this point, [reach] along the predicted path.
                val f = left / d
                out[m * 2] = (px + (x - px) * f).toFloat()
                out[m * 2 + 1] = (py + (y - py) * f).toFloat()
                return m + 1
            }
            left -= d
            out[m * 2] = x.toFloat()
            out[m * 2 + 1] = y.toFloat()
            m++
            px = x
            py = y
        }
        return m
    }

    /** How far (px, along the predicted path) the prediction may reach now, for a tip of [radius]. */
    fun reach(radius: Double): Double {
        if (size < 2 || radius <= 0) return 0.0
        val now = ts[head]
        if (now - ts[(head - size + 1 + HISTORY) % HISTORY] < 2 * windowMs) return 0.0
        val x2 = xs[head]
        val y2 = ys[head]
        val p2 = ps[head]
        sampleAt(now - windowMs)
        val x1 = atX
        val y1 = atY
        val p1 = atP
        sampleAt(now - 2 * windowMs)
        val ax = x1 - atX
        val ay = y1 - atY
        val bx = x2 - x1
        val by = y2 - y1
        val before = sqrt(ax * ax + ay * ay)
        val after = sqrt(bx * bx + by * by)
        if (after <= 0.0 || before <= 0.0) return 0.0
        val slowing = ramp(after / before, slowNone, slowFull)
        val angle = acos(((ax * bx + ay * by) / (before * after)).coerceIn(-1.0, 1.0))
        val turning = 1 - ramp(angle, turnFull, turnNone)
        val lifting = (1 - ramp(p1 - p2, liftFull, liftNone)) * ramp(p2, pressureNone, pressureFull)
        val scale = slowing * turning * lifting
        if (scale <= 0.0) return 0.0
        // A chord of length L leaves a circle of curvature k by about k L² / 2.
        val curvature = angle / ((before + after) / 2)
        val bend = if (curvature > 0) sqrt(2 * bendRadii * radius / curvature) else Double.MAX_VALUE
        val speed = after / windowMs
        return scale * min(min(speedReach * speed * horizonMs, maxRadii * radius), bend)
    }

    /** Sets [atX], [atY], [atP] to the position and pressure at [timeMs] (interpolated; clamped to the oldest sample). */
    private fun sampleAt(timeMs: Double) {
        var i = head
        for (k in 1 until size) {
            val older = (i - 1 + HISTORY) % HISTORY
            if (ts[older] <= timeMs) {
                val span = ts[i] - ts[older]
                val f = if (span > 0) ((timeMs - ts[older]) / span).coerceIn(0.0, 1.0) else 1.0
                atX = xs[older] + (xs[i] - xs[older]) * f
                atY = ys[older] + (ys[i] - ys[older]) * f
                atP = ps[older] + (ps[i] - ps[older]) * f
                return
            }
            i = older
        }
        atX = xs[i]
        atY = ys[i]
        atP = ps[i]
    }

    private fun ramp(v: Double, lo: Double, hi: Double): Double = ((v - lo) / (hi - lo)).coerceIn(0.0, 1.0)

    // Chosen by replaying the Ink Lab recordings (WetInkPredictionTest; docs/INK_LAB.md,
    // "Prediction"): longer horizons and caps buy little lead in real S Pen writing and cost
    // overshoot; the gates remove the pen-up flick.
    companion object {
        const val HORIZON_MS = 10.0
        const val MAX_RADII = 6.0
        const val SPEED_REACH = 1.0
        const val BEND_RADII = 0.25
        const val WINDOW_MS = 8.0
        const val SLOW_NONE = 0.8
        const val SLOW_FULL = 1.0
        const val TURN_FULL = 0.26 // 15°
        const val TURN_NONE = 0.79 // 45°
        const val LIFT_FULL = 0.02
        const val LIFT_NONE = 0.08
        const val PRESSURE_NONE = 0.05
        const val PRESSURE_FULL = 0.15

        /** Shorter than this (px) is not worth drawing. */
        const val MIN_REACH_PX = 0.25

        /** Samples kept: two windows at up to 1 kHz, with room to spare. */
        const val HISTORY = 32

        /** The most predicted points [filter] is given (the predictor's are cut to this). */
        const val MAX_POINTS = 32
    }
}
