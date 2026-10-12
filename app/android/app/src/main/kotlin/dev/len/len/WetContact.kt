package dev.len.len

import android.graphics.RectF
import android.os.Build
import android.view.MotionEvent

/**
 * One stylus contact of the low-latency overlay: its samples (in Flutter
 * view pixels) from pen-down, and once Dart has said how it looks (`begin`),
 * the [WetInkModel] that turns them into the same ink Flutter draws.
 */
internal class WetContact(val device: Int, val downMs: Long) {
    private val samples = Samples()
    private var model: WetInkModel? = null
    private var color = 0

    /** The writing area (Flutter view px); ink outside it is not drawn. */
    var clip = RectF()
        private set

    val began get() = model != null

    /** When Dart said the committed stroke is in a built frame (-1: not yet). */
    var endedAtMs = -1L

    /** When the pen was lifted (-1: still down). */
    var liftedAtMs = -1L
        private set

    /**
     * Whether to draw the tip: the line from the end of the ink to the newest
     * sample and the predicted points after it. False draws only the
     * model's ink (e.g. a mode that smooths heavily, where the raw sample
     * and its extrapolation would stick out).
     */
    var predicts = true
        set(value) {
            if (field != value) tipVersion++
            field = value
        }

    /**
     * The predictor's points after the newest sample, as (x, y, ms after it)
     * triples: [WetInkTip.predict] fills it, then [predicted] says how many.
     * Reused for every event.
     */
    val rawPrediction = FloatArray(3 * WetInkPrediction.MAX_POINTS)
    private var rawCount = 0

    /** How far ahead (ms) [rawPrediction] needs to reach. */
    val predictionMs get() = policy.horizonMs

    // What of the prediction to draw, from the samples so far; its output.
    private val policy = WetInkPrediction()
    private val drawn = FloatArray(2 * WetInkPrediction.MAX_POINTS)

    // Changes whenever the tip may (prediction, [predicts]).
    private var tipVersion = 0

    /** The newest sample's time (ns). */
    var newestNs = 0L
        private set

    // The last [ink] and what it was made of.
    private var ink: WetInkLayer.Ink? = null
    private var inkFrom = -1
    private var inkSize = -1
    private var inkTipVersion = -1

    fun matches(device: Any?, downUs: Any?): Boolean =
        (device as? Number)?.toInt() == this.device &&
            downUs is Number && Math.round(downUs.toDouble() / 1000) == downMs

    /** Index in [event] of this contact's pointer, or -1. */
    fun indexIn(event: MotionEvent): Int {
        if (liftedAtMs >= 0) return -1
        for (p in 0 until event.pointerCount) {
            if (StylusCapture.deviceOf(event, p) == device) return p
        }
        return -1
    }

    /** Adds the samples of pointer [p] of [event]; [lift] marks the pen-up. */
    fun add(event: MotionEvent, p: Int, dx: Float, dy: Float, lift: Boolean = false) {
        val range = event.device?.getMotionRange(MotionEvent.AXIS_PRESSURE)
        val min = range?.min ?: 0f
        val span = range?.range ?: 1f
        for (h in 0 until event.historySize) {
            val raw = event.getHistoricalPressure(p, h)
            add(
                (event.getHistoricalX(p, h) + dx).toDouble(),
                (event.getHistoricalY(p, h) + dy).toDouble(),
                // Normalised as Dart does; the model filters it like `PressureFilter`.
                if (span > 0) ((raw - min) / span).toDouble() else 0.5,
                event.getHistoricalEventTime(h),
                lift = false,
            )
        }
        val raw = event.getPressure(p)
        add(
            (event.getX(p) + dx).toDouble(),
            (event.getY(p) + dy).toDouble(),
            if (span > 0) ((raw - min) / span).toDouble() else 0.5,
            event.eventTime,
            lift,
        )
        newestNs = if (Build.VERSION.SDK_INT >= 34) event.eventTimeNanos else event.eventTime * 1_000_000
        if (lift) {
            liftedAtMs = event.eventTime
            tipVersion++ // No tip from now on.
        }
    }

    /**
     * Takes the first [count] triples of [rawPrediction] as the prediction
     * after the newest sample (0: none, as at the pen-up).
     */
    fun predicted(count: Int) {
        if (count == 0 && rawCount == 0) return
        rawCount = count
        tipVersion++
    }

    private fun add(x: Double, y: Double, pressure: Double, timeMs: Long, lift: Boolean) {
        samples.add(x, y, pressure, timeMs)
        policy.add(x, y, pressure, timeMs.toDouble())
        model?.add(x, y, pressure, timeMs, lift)
    }

    /**
     * Drawn from the style the stylus was armed with, until Dart's `begin`
     * confirms it (or `skip` says it is no ink); since when.
     */
    var provisionalSinceMs = -1L

    /**
     * Starts drawing (or restyles: Dart's style replaces the armed one):
     * replays the samples so far into [model].
     */
    fun begin(color: Int, model: WetInkModel, clip: RectF) {
        this.color = color
        this.clip = clip
        inkFrom = -1
        for (i in 0 until samples.size) {
            val lift = liftedAtMs >= 0 && i == samples.size - 1
            model.add(samples.x(i), samples.y(i), samples.pressure(i), samples.time(i), lift)
        }
        this.model = model
    }

    /**
     * The ink Flutter may not show yet, given that its frames on screen
     * contain the input up to [shownUpToMs]; the same object while that
     * does not change. Null when there is none.
     */
    fun ink(shownUpToMs: Double): WetInkLayer.Ink? {
        val m = model ?: return null
        val n = m.samples.size
        val from = m.tailStart(0.0, shownUpToMs, -1.0)
        if (from == inkFrom && n == inkSize && tipVersion == inkTipVersion) return ink
        inkFrom = from
        inkSize = n
        inkTipVersion = tipVersion
        if (from >= n) {
            ink = null
            return null
        }
        val hulls = toFloats(m.segments(from, n))
        ink = WetInkLayer.Ink(color, clip, hulls, tipOf(hulls))
        return ink
    }

    /**
     * The tip, as (x, y, radius) triples at the end's radius: from the end of
     * the ink through the newest sample (not yet a point if it is very close)
     * to the predicted points [WetInkPrediction] keeps. None once lifted (the
     * ink is then complete: the pen-up hook may have been cut, and the line
     * to the raw sample would draw it) or when not [predicts].
     */
    private fun tipOf(hulls: FloatArray): FloatArray {
        if (!predicts || liftedAtMs >= 0 || hulls.size < 3 || samples.size == 0) return NO_TIP
        val end = hulls.size - 3
        val r = hulls[end + 2]
        val m = policy.filter(rawPrediction, rawCount, r.toDouble(), drawn)
        // A new array: the renderer reads it on its own thread.
        val tip = FloatArray(3 * (2 + m))
        tip[0] = hulls[end]
        tip[1] = hulls[end + 1]
        tip[2] = r
        val last = samples.size - 1
        tip[3] = samples.x(last).toFloat()
        tip[4] = samples.y(last).toFloat()
        tip[5] = r
        for (i in 0 until m) {
            tip[6 + i * 3] = drawn[i * 2]
            tip[7 + i * 3] = drawn[i * 2 + 1]
            tip[8 + i * 3] = r
        }
        return tip
    }

    private fun toFloats(v: DoubleArray) = FloatArray(v.size) { v[it].toFloat() }

    private companion object {
        val NO_TIP = FloatArray(0)
    }

    /** Growable (x, y, normalised pressure, time) storage of the raw samples. */
    private class Samples {
        private var xyp = DoubleArray(3 * 512)
        private var times = LongArray(512)
        var size = 0
            private set

        fun add(x: Double, y: Double, pressure: Double, timeMs: Long) {
            if (size == times.size) {
                xyp = xyp.copyOf(xyp.size * 2)
                times = times.copyOf(times.size * 2)
            }
            xyp[size * 3] = x
            xyp[size * 3 + 1] = y
            xyp[size * 3 + 2] = pressure
            times[size] = timeMs
            size++
        }

        fun x(i: Int) = xyp[i * 3]
        fun y(i: Int) = xyp[i * 3 + 1]
        fun pressure(i: Int) = xyp[i * 3 + 2]
        fun time(i: Int) = times[i]
    }
}
