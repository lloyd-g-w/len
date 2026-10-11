package dev.len.len

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
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
 * `begin` names the stylus contact, its colour, radius per pressure, the
 * outline's rules (`WetInkShape`) and where the ink starts; `progress`
 * reports which input Flutter has drawn; `end` that the finished stroke is
 * on screen. [WetInkModel] (a port of the Dart model the Ink Lab measures)
 * applies the outline's rules, so the overlay draws the same ink Flutter
 * will, and only shows points newer than the progress reported two
 * messages before the latest: Flutter presents a frame about two frames
 * after building it.
 *
 * New points are drawn incrementally into the front buffer; each commit
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
    private var model: WetInkModel? = null

    // Set by Dart.
    private var drawing = false
    private var endedAtMs = -1L
    @Volatile private var color = Color.BLACK
    private var drawn = 0
    // The latest three `progress` values (oldest first).
    private val progress = ArrayDeque<Double>()
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
                model = null
                samples.clear()
                add(event, p, -1, dx, dy, lift = false)
            }
            MotionEvent.ACTION_MOVE, MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val p = indexOfContact(event) ?: return
                for (h in 0 until event.historySize) add(event, p, h, dx, dy, lift = false)
                val up = event.actionMasked != MotionEvent.ACTION_MOVE && event.actionIndex == p
                add(event, p, -1, dx, dy, lift = up)
                if (up) lifted = true
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
                val radii = message[4] as DoubleArray
                val shape = WetInkShape.of(message[5] as DoubleArray) ?: return
                if (radii.isEmpty()) return
                val startMs = Math.floorDiv((message[6] as Number).toLong(), 1000L)
                val m = WetInkModel(radii, shape, frameMs(), startMs)
                for (i in 0 until samples.size) {
                    m.add(samples.x(i), samples.y(i), samples.pressure(i), samples.time(i), lift = false)
                }
                model = m
                drawing = true
                drawn = 0
                progress.clear()
                drawNew()
            }
            "progress" -> if (drawing) {
                pushProgress((message[1] as Number).toDouble() / 1000)
                scheduleCommit(0)
            }
            "end" -> {
                val dev = (message[1] as Number).toInt()
                val down = Math.round((message[2] as Number).toDouble() / 1000)
                if (drawing && dev == device && down == downMs) {
                    // The frame showing the committed stroke counts as a progress message.
                    progress.lastOrNull()?.let { pushProgress(it) }
                    stop(SystemClock.uptimeMillis())
                }
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

    /** Appends sample [h] (or the current one for -1) of pointer [p]; [lift] marks the pen-up sample. */
    private fun add(event: MotionEvent, p: Int, h: Int, dx: Float, dy: Float, lift: Boolean) {
        val raw = if (h < 0) event.getPressure(p) else event.getHistoricalPressure(p, h)
        val range = event.device?.getMotionRange(MotionEvent.AXIS_PRESSURE)
        val min = range?.min ?: 0f
        val span = range?.range ?: 1f
        // Normalised as Dart does; the model filters it like `PressureFilter`.
        val norm = if (span > 0) ((raw - min) / span).toDouble() else 0.5
        val x = ((if (h < 0) event.getX(p) else event.getHistoricalX(p, h)) + dx).toDouble()
        val y = ((if (h < 0) event.getY(p) else event.getHistoricalY(p, h)) + dy).toDouble()
        val time = if (h < 0) event.eventTime else event.getHistoricalEventTime(h)
        samples.add(x, y, norm, time)
        model?.add(x, y, norm, time, lift)
    }

    private fun pushProgress(ms: Double) {
        progress.addLast(ms)
        while (progress.size > 3) progress.removeFirst()
    }

    /** Draws the points not yet in the front buffer. */
    private fun drawNew() {
        val renderer = layer?.renderer ?: return
        val m = model ?: return
        val n = m.samples.size
        if (!drawing || n == 0 || drawn >= n) return
        renderer.renderFrontBufferedLayer(toFloats(m.segments(maxOf(0, drawn - 1), n)))
        drawn = n
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

    /** The ink Flutter may not have presented yet, as (x, y, radius) triples. */
    private fun tail(): FloatArray {
        val m = model ?: return FloatArray(0)
        if (!drawing && endedAtMs < 0) return FloatArray(0)
        // The input of the frame Flutter shows, at the latest: the progress
        // reported two messages before the latest one.
        val shown = if (progress.size >= 3) progress.first() else downMs.toDouble()
        val now = SystemClock.uptimeMillis().toDouble()
        val from = m.tailStart(now, shown, endedAtMs.toDouble())
        if (from >= m.samples.size) return FloatArray(0)
        return toFloats(m.segments(from, m.samples.size))
    }

    private fun frameMs(): Double {
        val rate = host.flutterView()?.display?.refreshRate ?: 60f
        return 1000.0 / rate.coerceIn(30f, 240f)
    }

    private fun toFloats(v: DoubleArray) = FloatArray(v.size) { v[it].toFloat() }

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
        private val frontPath = Path()
        private val tailPath = Path()
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
                style = Paint.Style.FILL
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
                        drawHulls(canvas, paint, frontPath, param)
                    }

                    override fun onDrawMultiBufferedLayer(
                        canvas: Canvas,
                        bufferWidth: Int,
                        bufferHeight: Int,
                        params: Collection<FloatArray>,
                    ) {
                        canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
                        paint.color = color()
                        drawHulls(canvas, paint, tailPath, tail)
                    }
                },
            )

        fun release() {
            renderer.release(true)
            (view.parent as? ViewGroup)?.removeView(view)
        }
    }

    /** Growable (x, y, normalised pressure, time) storage of one contact's raw samples. */
    private class Samples {
        private var xyp = DoubleArray(3 * 512)
        private var times = LongArray(512)
        var size = 0
            private set

        fun clear() {
            size = 0
        }

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

    companion object {
        const val CHANNEL = "len/low_latency_ink"
        private const val TAG = "LenWetInk"

        /**
         * The ink of consecutive (x, y, radius) triples: each pair is the hull
         * of its two circles (a tapered capsule); one triple is a dot.
         */
        fun drawHulls(canvas: Canvas, paint: Paint, path: Path, xyr: FloatArray) {
            val n = xyr.size / 3
            if (n == 0) return
            canvas.drawCircle(xyr[0], xyr[1], xyr[2], paint)
            for (i in 1 until n) {
                val o = i * 3
                val ax = xyr[o - 3]
                val ay = xyr[o - 2]
                val ra = xyr[o - 1]
                val bx = xyr[o]
                val by = xyr[o + 1]
                val rb = xyr[o + 2]
                canvas.drawCircle(bx, by, rb, paint)
                val dx = bx - ax
                val dy = by - ay
                val len = Math.hypot(dx.toDouble(), dy.toDouble()).toFloat()
                if (len <= Math.abs(ra - rb)) continue // One circle holds the other.
                // The tangents touch where the normal n has n·u = (ra − rb) / len.
                val ux = dx / len
                val uy = dy / len
                val c = (ra - rb) / len
                val s = Math.sqrt((1 - c * c).toDouble()).toFloat()
                val n1x = c * ux - s * uy
                val n1y = c * uy + s * ux
                val n2x = c * ux + s * uy
                val n2y = c * uy - s * ux
                path.rewind()
                path.moveTo(ax + ra * n1x, ay + ra * n1y)
                path.lineTo(bx + rb * n1x, by + rb * n1y)
                path.lineTo(bx + rb * n2x, by + rb * n2y)
                path.lineTo(ax + ra * n2x, ay + ra * n2y)
                path.close()
                canvas.drawPath(path, paint)
            }
        }
    }
}
