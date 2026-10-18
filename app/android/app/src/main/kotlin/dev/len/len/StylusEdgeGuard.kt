package dev.len.len

import android.graphics.Rect
import android.os.Build
import android.view.MotionEvent
import android.view.View

/**
 * Keeps the system's Back gesture off a stylus writing from the screen's
 * left or right edge (gesture navigation, Android 10+): while a stylus
 * hovers over or touches the Flutter view, a [StylusEdgeBand] around its
 * y is excluded from system gestures at both edges
 * (`View.setSystemGestureExclusionRects`). Fingers and mice never set it,
 * so a finger's Back keeps working.
 *
 * Only while Dart says an editor is showing ([enabled], the `edges`
 * message on `len/low_latency_ink`). Hover comes before contact, so the
 * band is in place before the system sees the pen's down. Watches the
 * events natively ([MainActivity]'s dispatch), with no round trip to Dart.
 */
class StylusEdgeGuard(private val host: WetInkOverlay.Host) {
    private var band: StylusEdgeBand? = null
    private var view: View? = null

    /** Whether an editor is showing (the band may be set). */
    var enabled = false
        set(on) {
            field = on
            if (!on) clear()
        }

    /** Observes [event] (hover or touch), [dy] shifting window y into the Flutter view's. */
    fun onMotion(event: MotionEvent, dy: Float) {
        if (Build.VERSION.SDK_INT < 29 || !enabled) return
        when (event.actionMasked) {
            MotionEvent.ACTION_HOVER_ENTER, MotionEvent.ACTION_HOVER_MOVE,
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN, MotionEvent.ACTION_MOVE -> {
                val p = stylusPointer(event) ?: return
                follow(event.getY(p) + dy)
            }
            MotionEvent.ACTION_HOVER_EXIT, MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP ->
                if (StylusCapture.isStylus(event, event.actionIndex)) leave()
            MotionEvent.ACTION_CANCEL -> if (stylusPointer(event) != null) leave()
        }
    }

    private fun stylusPointer(event: MotionEvent): Int? {
        for (p in 0 until event.pointerCount) if (StylusCapture.isStylus(event, p)) return p
        return null
    }

    private fun follow(y: Float) {
        val v = host.flutterView() ?: return
        v.removeCallbacks(clearNow)
        val b = band ?: run {
            val density = v.resources.displayMetrics.density
            StylusEdgeBand(
                (StylusEdgeBand.BAND_DP * density).toInt(),
                StylusEdgeBand.STEP_DP * density,
            ).also { band = it }
        }
        if (!b.follow(y, v.height) && view === v) return
        view = v
        v.systemGestureExclusionRects = listOf(Rect(0, b.top, v.width, b.bottom))
    }

    /**
     * The stylus left (or lifted): the band goes a little later. A pen
     * landing reports leaving hover just before its down, and lifting
     * hovers again right after: neither should drop the band in between.
     */
    private fun leave() {
        val v = view ?: return
        v.removeCallbacks(clearNow)
        v.postDelayed(clearNow, LEAVE_GRACE_MS)
    }

    private val clearNow = Runnable { clear() }

    private fun clear() {
        val v = view ?: return
        v.removeCallbacks(clearNow)
        band?.clear()
        if (Build.VERSION.SDK_INT >= 29) v.systemGestureExclusionRects = emptyList()
        view = null
    }

    companion object {
        /** How long (ms) the band outlasts the stylus leaving. */
        const val LEAVE_GRACE_MS = 250L
    }
}
