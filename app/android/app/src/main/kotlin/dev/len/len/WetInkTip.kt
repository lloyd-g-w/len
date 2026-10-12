package dev.len.len

import android.util.Log
import android.view.MotionEvent
import android.view.View
import androidx.input.motionprediction.MotionEventPredictor

/**
 * Motion prediction for the overlay's tip (androidx.input: Android's own
 * predictor where the device has one, a Kalman filter otherwise). The
 * predicted points are only ever drawn, never stored: each event replaces
 * them, and [WetInkPrediction] decides how much of them to draw.
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
     * Where pointer [pointerId] is predicted to be over the next [maxMs]
     * milliseconds after [nowMs] (the newest event's time): writes (x, y, ms
     * after [nowMs]) triples into [out], in Flutter view pixels (window
     * coordinates shifted by [dx], [dy]), at most `out.size / 3` of them, and
     * returns how many. [WetInkPrediction] decides how much of it to draw.
     */
    fun predict(pointerId: Int, nowMs: Long, dx: Float, dy: Float, maxMs: Double, out: FloatArray): Int {
        val predicted = try {
            predictor?.predict()
        } catch (e: RuntimeException) {
            null
        } ?: return 0
        try {
            val p = predicted.findPointerIndex(pointerId)
            if (p < 0) return 0
            val max = out.size / 3
            var n = 0
            for (h in 0..predicted.historySize) {
                if (n == max) break
                val current = h == predicted.historySize
                val ms = (if (current) predicted.eventTime else predicted.getHistoricalEventTime(h)) - nowMs
                if (ms > maxMs) break
                out[n * 3] = (if (current) predicted.getX(p) else predicted.getHistoricalX(p, h)) + dx
                out[n * 3 + 1] = (if (current) predicted.getY(p) else predicted.getHistoricalY(p, h)) + dy
                out[n * 3 + 2] = ms.toFloat()
                n++
            }
            return n
        } finally {
            predicted.recycle()
        }
    }

    companion object {
        private const val TAG = "LenWetInk"
    }
}
