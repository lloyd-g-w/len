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

    /** The predicted tip, (x, y) pairs after the newest sample, or null. */
    var prediction: FloatArray? = null

    /** The newest sample's time (ns). */
    var newestNs = 0L
        private set

    // The last [ink] and what it was made of.
    private var ink: WetInkLayer.Ink? = null
    private var inkFrom = -1
    private var inkSize = -1
    private var inkPrediction: FloatArray? = null

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
        if (lift) liftedAtMs = event.eventTime
    }

    private fun add(x: Double, y: Double, pressure: Double, timeMs: Long, lift: Boolean) {
        samples.add(x, y, pressure, timeMs)
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
        val predicted = prediction
        if (from == inkFrom && n == inkSize && predicted === inkPrediction) return ink
        inkFrom = from
        inkSize = n
        inkPrediction = predicted
        if (from >= n) {
            ink = null
            return null
        }
        val hulls = toFloats(m.segments(from, n))
        ink = WetInkLayer.Ink(color, clip, hulls, tipOf(hulls, predicted))
        return ink
    }

    /**
     * The predicted tip: from the end of the ink through the newest sample
     * (not yet a point if it is very close) to the [predicted] points, at
     * the end's radius.
     */
    private fun tipOf(hulls: FloatArray, predicted: FloatArray?): FloatArray {
        if (hulls.size < 3 || samples.size == 0) return FloatArray(0)
        val end = hulls.size - 3
        val r = hulls[end + 2]
        val points = ArrayList<Float>(12)
        points.add(hulls[end])
        points.add(hulls[end + 1])
        points.add(r)
        val last = samples.size - 1
        points.add(samples.x(last).toFloat())
        points.add(samples.y(last).toFloat())
        points.add(r)
        if (predicted != null && liftedAtMs < 0) {
            for (i in 0 until predicted.size / 2) {
                points.add(predicted[i * 2])
                points.add(predicted[i * 2 + 1])
                points.add(r)
            }
        }
        return points.toFloatArray()
    }

    private fun toFloats(v: DoubleArray) = FloatArray(v.size) { v[it].toFloat() }

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
