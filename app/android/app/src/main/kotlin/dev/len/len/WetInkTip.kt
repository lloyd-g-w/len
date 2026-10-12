package dev.len.len

import android.util.Log
import android.view.MotionEvent
import android.view.View
import androidx.input.motionprediction.MotionEventPredictor

/**
 * Motion prediction for the overlay's tip (androidx.input: Android's own
 * predictor where the device has one, a Kalman filter otherwise). The
 * predicted points are only ever drawn, never stored: each event replaces
 * them.
 */
internal class WetInkTip(private val view: View) {
    private var predictor: MotionEventPredictor? = null

    /** Starts a new gesture at its down [event]. */
    fun start(event: MotionEvent) {
        if (predictor == null) predictor = MotionEventPredictor.newInstance(view)
        record(event)
    }

    /** Feeds [event] (every event of the gesture, as the predictor requires). */
    fun record(event: MotionEvent) {
        try {
            predictor?.record(event)
        } catch (e: IllegalArgumentException) {
            // An inconsistent stream (e.g. a gesture that began before we
            // looked): start over with the next one.
            Log.w(TAG, "prediction reset", e)
            predictor = null
        }
    }

    /**
     * Where pointer [pointerId] is predicted to be over the next few
     * milliseconds, as (x, y) pairs in Flutter view pixels (window
     * coordinates shifted by [dx], [dy]), at most [MAX_MS] after [nowMs]
     * (the newest event's time).
     */
    fun predict(pointerId: Int, nowMs: Long, dx: Float, dy: Float): FloatArray? {
        val predicted = try {
            predictor?.predict()
        } catch (e: RuntimeException) {
            null
        } ?: return null
        try {
            val p = predicted.findPointerIndex(pointerId)
            if (p < 0) return null
            val out = ArrayList<Float>(8)
            for (h in 0 until predicted.historySize) {
                if (predicted.getHistoricalEventTime(h) - nowMs > MAX_MS) break
                out.add(predicted.getHistoricalX(p, h) + dx)
                out.add(predicted.getHistoricalY(p, h) + dy)
            }
            if (predicted.eventTime - nowMs <= MAX_MS) {
                out.add(predicted.getX(p) + dx)
                out.add(predicted.getY(p) + dy)
            }
            return out.toFloatArray()
        } finally {
            predicted.recycle()
        }
    }

    companion object {
        private const val TAG = "LenWetInk"

        /** The furthest ahead a predicted point may be (ms). */
        const val MAX_MS = 20L
    }
}
