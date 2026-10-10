package dev.len.len

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.PorterDuff
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.MotionEvent
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import androidx.annotation.RequiresApi
import androidx.graphics.lowlatency.CanvasFrontBufferedRenderer
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec

/**
 * "Low-latency ink" (experimental): draws the tip of the stroke being
 * written into a front-buffered overlay above the Flutter view, as soon as
 * each `MotionEvent` arrives, instead of waiting for Flutter's next frame.
 *
 * Dart decides what is ink (`lib/platform/stylus_samples_native.dart`):
 * `begin` names the stylus contact and its colour and radius per pressure;
 * `progress` reports which input Flutter has drawn; `end` that the
 * finished stroke is on screen. The overlay only ever shows samples Flutter
 * may not have presented yet (plus a margin of two frames), so its ink sits
 * on top of identical Flutter ink and then disappears.
 *
 * New segments are drawn incrementally into the front buffer; each commit
 * (once per Flutter frame, and while a tail remains) atomically clears it
 * and redraws only the remaining tail into the multi-buffered layer.
 */
class WetInkOverlay(private val host: Host, messenger: BinaryMessenger) {
    /** Where the overlay lives: the Flutter view and its parent. */
    interface Host {
        fun flutterView(): View?
    }

    private val channel = BasicMessageChannel(messenger, CHANNEL, StandardMessageCodec.INSTANCE)
    private val handler = Handler(Looper.getMainLooper())
    private var enabled = false
    private var layer: Layer? = null

    // The current stylus contact, tracked from its down event.
    private var device = -1
    private var downMs = 0L
    private var lifted = true
    private val samples = Samples()
    private var pressure = -1f

    // Set by Dart.
    private var drawing = false
    private var endedAtMs = -1L
    @Volatile private var color = Color.BLACK
    private var radii = FloatArray(0)
    private var drawn = 0
    private var flutterUpToMs = 0.0
    private var commitPending = false

    init {
        channel.setMessageHandler { message, reply ->
            try {
                handle(message as? List<*>)
            } catch (e: RuntimeException) {
                Log.w(TAG, "bad message", e)
            }
            reply.reply(null)
        }
    }

    /** Observes [event] (window coordinates shifted by [dx], [dy] into the Flutter view). */
    fun onTouch(event: MotionEvent, dx: Float, dy: Float, capture: StylusCapture) {
        if (!enabled) return
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val p = event.actionIndex
                if (event.getToolType(p) != MotionEvent.TOOL_TYPE_STYLUS) return
                device = StylusCapture.deviceOf(event, p)
                downMs = capture.downTimeOf(event, event.getPointerId(p))
                lifted = false
                drawing = false
                endedAtMs = -1
                pressure = -1f
                samples.clear()
                add(event, p, -1, dx, dy)
            }
            MotionEvent.ACTION_MOVE, MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val p = indexOfContact(event) ?: return
                for (h in 0 until event.historySize) add(event, p, h, dx, dy)
                add(event, p, -1, dx, dy)
                if (event.actionMasked != MotionEvent.ACTION_MOVE && event.actionIndex == p) {
                    lifted = true
                }
                drawNew()
            }
            MotionEvent.ACTION_CANCEL -> if (!lifted) {
                lifted = true
                if (drawing) stop(SystemClock.uptimeMillis() - 1000) // Flutter drops it.
            }
        }
    }

    /** Releases the overlay (activity going away). */
    fun dispose() {
        handler.removeCallbacksAndMessages(null)
        commitPending = false
        drawing = false
        layer?.release()
        layer = null
    }

    private fun handle(message: List<*>?) {
        when (message?.getOrNull(0)) {
            "enable" -> {
                enabled = message[1] == true
                if (!enabled) dispose() else if (layer == null) layer = createLayer()
            }
            "begin" -> {
                val dev = (message[1] as Number).toInt()
                val down = Math.round((message[2] as Number).toDouble() / 1000)
                if (dev != device || down != downMs || lifted) return
                color = (message[3] as Number).toLong().toInt()
                radii = (message[4] as DoubleArray).map { it.toFloat() }.toFloatArray()
                if (radii.isEmpty()) return
                drawing = true
                drawn = 0
                flutterUpToMs = downMs.toDouble()
                drawNew()
            }
            "progress" -> if (drawing) {
                flutterUpToMs = (message[1] as Number).toDouble() / 1000
                scheduleCommit(0)
            }
            "end" -> {
                val dev = (message[1] as Number).toInt()
                val down = Math.round((message[2] as Number).toDouble() / 1000)
                if (drawing && dev == device && down == downMs) stop(SystemClock.uptimeMillis())
            }
        }
    }

    /** Index in [event] of the tracked contact's pointer, if present. */
    private fun indexOfContact(event: MotionEvent): Int? {
        if (lifted) return null
        for (p in 0 until event.pointerCount) {
            if (StylusCapture.deviceOf(event, p) == device) return p
        }
        return null
    }

    /** Appends sample [h] (or the current one for -1) of pointer [p]. */
    private fun add(event: MotionEvent, p: Int, h: Int, dx: Float, dy: Float) {
        val raw = if (h < 0) event.getPressure(p) else event.getHistoricalPressure(p, h)
        val range = event.device?.getMotionRange(MotionEvent.AXIS_PRESSURE)
        val min = range?.min ?: 0f
        val span = range?.range ?: 1f
        val norm = if (span > 0) ((raw - min) / span).coerceIn(0.05f, 1f) else 0.5f
        // Same smoothing as Dart's PressureFilter.
        pressure = if (pressure < 0) norm else pressure * 0.65f + norm * 0.35f
        samples.add(
            (if (h < 0) event.getX(p) else event.getHistoricalX(p, h)) + dx,
            (if (h < 0) event.getY(p) else event.getHistoricalY(p, h)) + dy,
            pressure,
            if (h < 0) event.eventTime else event.getHistoricalEventTime(h),
        )
    }

    /** Draws the samples not yet in the front buffer. */
    private fun drawNew() {
        val renderer = layer?.renderer ?: return
        if (!drawing || samples.size == 0 || drawn >= samples.size) return
        renderer.renderFrontBufferedLayer(segment(maxOf(0, drawn - 1), samples.size))
        drawn = samples.size
    }

    private fun stop(atMs: Long) {
        drawing = false
        endedAtMs = atMs
        scheduleCommit(0)
    }

    private fun scheduleCommit(delayMs: Long) {
        if (commitPending) return
        commitPending = true
        handler.postDelayed(commit, delayMs)
    }

    private val commit = Runnable {
        commitPending = false
        val layer = layer ?: return@Runnable
        val tail = tail()
        layer.tail = tail
        layer.renderer.commit()
        if (tail.isNotEmpty()) scheduleCommit(frameMs().toLong().coerceAtLeast(4))
    }

    /** The samples Flutter may not have presented yet, as (x, y, radius) triples. */
    private fun tail(): FloatArray {
        val now = SystemClock.uptimeMillis()
        val frame = frameMs()
        if (endedAtMs >= 0 && now - endedAtMs >= 2 * frame) return FloatArray(0)
        if (!drawing && endedAtMs < 0) return FloatArray(0)
        // Flutter builds a frame, then rasterises and presents it about two
        // frames later; and never trust it to lag more than five frames.
        val cutoff = maxOf(flutterUpToMs - 2 * frame, now - 5 * frame)
        var from = samples.size
        while (from > 0 && samples.time(from - 1) > cutoff) from--
        if (from == samples.size) return FloatArray(0)
        return segment(maxOf(0, from - 1), samples.size)
    }

    private fun frameMs(): Double {
        val rate = host.flutterView()?.display?.refreshRate ?: 60f
        return 1000.0 / rate.coerceIn(30f, 240f)
    }

    /** Samples [from] until [to] as (x, y, radius) triples. */
    private fun segment(from: Int, to: Int): FloatArray {
        val out = FloatArray((to - from) * 3)
        for (i in from until to) {
            val o = (i - from) * 3
            out[o] = samples.x(i)
            out[o + 1] = samples.y(i)
            out[o + 2] = radiusAt(samples.pressure(i))
        }
        return out
    }

    private fun radiusAt(p: Float): Float {
        val t = p.coerceIn(0f, 1f) * (radii.size - 1)
        val i = t.toInt().coerceAtMost(radii.size - 2).coerceAtLeast(0)
        if (radii.size == 1) return radii[0]
        return radii[i] + (radii[i + 1] - radii[i]) * (t - i)
    }

    private fun createLayer(): Layer? {
        if (Build.VERSION.SDK_INT < 29) return null // Front-buffered rendering needs Android 10.
        val flutter = host.flutterView() ?: return null
        val parent = flutter.parent as? ViewGroup ?: return null
        return try {
            Layer(parent, flutter, { color })
        } catch (e: RuntimeException) {
            Log.w(TAG, "low-latency ink unavailable", e)
            null
        }
    }

    /** The overlay surface (same bounds as the Flutter view) and its front-buffered renderer. */
    @RequiresApi(29)
    private class Layer(parent: ViewGroup, flutter: View, color: () -> Int) {
        @Volatile var tail = FloatArray(0)
        private val view = SurfaceView(parent.context)
        val renderer: CanvasFrontBufferedRenderer<FloatArray>

        init {
            view.setZOrderMediaOverlay(true)
            view.holder.setFormat(PixelFormat.TRANSLUCENT)
            view.isClickable = false
            view.isFocusable = false
            view.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            val size = ViewGroup.LayoutParams.MATCH_PARENT
            parent.addView(view, parent.indexOfChild(flutter) + 1, ViewGroup.LayoutParams(size, size))
            val paint = Paint().apply {
                isAntiAlias = true
                style = Paint.Style.STROKE
                strokeCap = Paint.Cap.ROUND
            }
            renderer = createRenderer(view, paint, color)
        }

        private fun createRenderer(view: SurfaceView, paint: Paint, color: () -> Int) =
            CanvasFrontBufferedRenderer(
                view,
                object : CanvasFrontBufferedRenderer.Callback<FloatArray> {
                    override fun onDrawFrontBufferedLayer(
                        canvas: Canvas,
                        bufferWidth: Int,
                        bufferHeight: Int,
                        param: FloatArray,
                    ) {
                        paint.color = color()
                        drawSegments(canvas, paint, param)
                    }

                    override fun onDrawMultiBufferedLayer(
                        canvas: Canvas,
                        bufferWidth: Int,
                        bufferHeight: Int,
                        params: Collection<FloatArray>,
                    ) {
                        canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
                        paint.color = color()
                        drawSegments(canvas, paint, tail)
                    }
                },
            )

        fun release() {
            renderer.release(true)
            (view.parent as? ViewGroup)?.removeView(view)
        }
    }

    /** Growable (x, y, pressure, time) storage for one contact. */
    private class Samples {
        private var xyp = FloatArray(3 * 512)
        private var times = LongArray(512)
        var size = 0
            private set

        fun clear() {
            size = 0
        }

        fun add(x: Float, y: Float, pressure: Float, timeMs: Long) {
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

    companion object {
        const val CHANNEL = "len/low_latency_ink"
        private const val TAG = "LenWetInk"

        /** Round-capped segments between consecutive (x, y, radius) triples. */
        fun drawSegments(canvas: Canvas, paint: Paint, xyr: FloatArray) {
            val n = xyr.size / 3
            if (n == 1) {
                paint.style = Paint.Style.FILL
                canvas.drawCircle(xyr[0], xyr[1], xyr[2], paint)
                paint.style = Paint.Style.STROKE
                return
            }
            for (i in 1 until n) {
                val o = i * 3
                paint.strokeWidth = xyr[o - 1] + xyr[o + 2]
                canvas.drawLine(xyr[o - 3], xyr[o - 2], xyr[o], xyr[o + 1], paint)
            }
        }
    }
}
