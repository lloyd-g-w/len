package dev.len.len

import android.graphics.RectF
import android.os.Build
import android.os.SystemClock
import android.os.Trace
import android.util.Log
import android.view.Choreographer
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec

/**
 * Low-latency ink: draws the newest part of the stroke being written into a
 * front-buffered overlay ([WetInkLayer]) above the Flutter view as soon as
 * each `MotionEvent` arrives, a few frames before Flutter's own frame shows
 * it, with a short predicted tip.
 *
 * Dart decides what is ink (`lib/platform/stylus_samples_native.dart`):
 * `begin` names the stylus contact, its colour, radius per pressure, the
 * outline's rules ([WetInkShape]) and the writing area to clip to;
 * `progress` reports the newest input a built Flutter frame contains; `end`
 * that the frame showing the committed stroke was built; `cancel` that
 * Flutter no longer draws the contact as it was. [WetInkModel] (checked
 * against the Dart model the Ink Lab measures) applies the outline's rules,
 * so the overlay draws the same ink Flutter will, on top of it: only
 * opaque pens qualify, so where they overlap nothing changes.
 *
 * The overlay keeps each point until the Flutter frame showing it has been
 * on screen for sure: [SHOWN_AFTER_MS] after Dart reported building it.
 */
class WetInkOverlay(private val host: Host, messenger: BinaryMessenger) {
    /** Where the overlay lives: the Flutter view. */
    interface Host {
        fun flutterView(): View?
    }

    private val channel = BasicMessageChannel(messenger, CHANNEL, StandardMessageCodec.INSTANCE)
    private var layer: WetInkLayer? = null
    private var tip: WetInkTip? = null

    /**
     * The contact being written (null once lifted), the newest one (lifted
     * or not; `begin` may come after a quick dot's pen-up) and the ones
     * the overlay draws.
     */
    private var current: WetContact? = null
    private var latest: WetContact? = null
    private val contacts = ArrayList<WetContact>()

    // `progress` values (µs → ms of input time) with when they arrived, oldest first.
    private val progressAt = ArrayDeque<Long>()
    private val progressUpTo = ArrayDeque<Double>()

    // How a stroke starting now would look (Dart's `arm`, sent while the
    // stylus hovers over a surface) and when it came.
    private var armed: Style? = null
    private var armedAtMs = 0L

    private var shown = false
    private var ticking = false

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

    /** Creates the surface (if needed) so the first stroke is fast too. */
    fun attach() {
        if (Build.VERSION.SDK_INT < 29) return // Front-buffered rendering needs Android 10.
        val flutter = host.flutterView() ?: return
        if (layer?.isAbove(flutter) == true) return
        layer?.release()
        layer = null
        val parent = flutter.parent as? ViewGroup ?: return
        try {
            layer = WetInkLayer(parent, flutter)
            tip = WetInkTip(flutter)
        } catch (e: RuntimeException) {
            Log.w(TAG, "low-latency ink unavailable", e)
        }
    }

    /** Releases the overlay (activity going away). */
    fun dispose() {
        Choreographer.getInstance().removeFrameCallback(tick)
        ticking = false
        contacts.clear()
        current = null
        latest = null
        layer?.release()
        layer = null
    }

    /** Observes [event] (window coordinates shifted by [dx], [dy] into the Flutter view). */
    fun onTouch(event: MotionEvent, dx: Float, dy: Float, capture: StylusCapture) {
        if (layer == null) return
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val p = event.actionIndex
                if (event.getToolType(p) != MotionEvent.TOOL_TYPE_STYLUS) {
                    if (current != null) tip?.record(event)
                    return
                }
                // Samples as they come, not once per frame (S Pen: 240 Hz).
                host.flutterView()?.requestUnbufferedDispatch(event)
                val down = capture.downTimeOf(event, event.getPointerId(p))
                val contact = WetContact(StylusCapture.deviceOf(event, p), down)
                current = contact
                latest = contact
                tip?.start(event)
                contact.add(event, p, dx, dy)
                // Hovering just now with the pen tool: draw from the first
                // sample; Dart confirms (`begin`) or takes it back (`skip`).
                val style = armed
                val now = SystemClock.uptimeMillis()
                if (style != null && now - armedAtMs <= ARM_FRESH_MS && event.buttonState == 0) {
                    contact.begin(style.color, WetInkModel(style.radii, style.shape, frameMs()), style.clip)
                    contact.provisionalSinceMs = now
                    contacts.add(contact)
                    render()
                    startTicking()
                }
            }
            MotionEvent.ACTION_MOVE, MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val contact = current ?: return
                tip?.record(event)
                val p = contact.indexIn(event)
                if (p < 0) return
                val up = event.actionMasked != MotionEvent.ACTION_MOVE && event.actionIndex == p
                contact.add(event, p, dx, dy, lift = up)
                contact.prediction =
                    if (up) null else tip?.predict(event.getPointerId(p), event.eventTime, dx, dy)
                if (up) current = null
                if (contact.began) render()
            }
            MotionEvent.ACTION_CANCEL -> current?.let { contact ->
                current = null
                latest = null
                if (contacts.remove(contact)) render() // Flutter drops the stroke.
            }
        }
    }

    private fun handle(message: List<*>?) {
        val now = SystemClock.uptimeMillis()
        when (message?.getOrNull(0)) {
            "arm" -> {
                armed = if (message.size > 1) Style.of(message, 1) else null
                armedAtMs = now
            }
            "begin" -> {
                val contact = latest ?: return
                if (!contact.matches(message[1], message[2])) return
                if (contact.began && contact.provisionalSinceMs < 0) return
                val style = Style.of(message, 3) ?: return
                contact.begin(style.color, WetInkModel(style.radii, style.shape, frameMs()), style.clip)
                contact.provisionalSinceMs = -1
                if (contact !in contacts) contacts.add(contact)
                render()
            }
            "skip" -> contacts.find { it.matches(message[1], message[2]) }?.let {
                contacts.remove(it)
                render()
            }
            "progress" -> {
                val upTo = (message[1] as Number).toDouble() / 1000
                if (Trace.isEnabled()) {
                    Trace.beginSection("len.progress ${(upTo * 1e6).toLong()}")
                    Trace.endSection()
                }
                progressAt.addLast(now)
                progressUpTo.addLast(upTo)
            }
            "end" -> contacts.find { it.matches(message[1], message[2]) }?.endedAtMs = now
            "cancel" -> contacts.find { it.matches(message[1], message[2]) }?.let {
                contacts.remove(it)
                if (it === current) current = null
                render()
            }
        }
        if (contacts.isNotEmpty()) startTicking()
    }

    /** Input time of the newest Flutter frame that is on screen for sure at [now]. */
    private fun shownUpTo(now: Long): Double {
        var upTo = Double.NEGATIVE_INFINITY
        while (progressAt.size > 1 && now - progressAt[1] >= SHOWN_AFTER_MS) {
            progressAt.removeFirst()
            progressUpTo.removeFirst()
        }
        if (progressAt.isNotEmpty() && now - progressAt.first() >= SHOWN_AFTER_MS) upTo = progressUpTo.first()
        return upTo
    }

    /**
     * Once per display frame while there is ink: removes the strokes Flutter
     * surely shows by now. Only then is the overlay redrawn; a tail Flutter
     * has caught up with may stay until the next sample (it lies exactly on
     * Flutter's ink), which saves the renderer half its work.
     */
    private val tick = Choreographer.FrameCallback {
        ticking = false
        if (prune(SystemClock.uptimeMillis())) render()
        if (contacts.isNotEmpty()) startTicking()
    }

    /** Drops the contacts Flutter surely shows by [now]; whether there were any. */
    private fun prune(now: Long): Boolean = contacts.removeAll {
        // Shown by Flutter for sure, or not confirmed by Dart (it went away).
        (it.endedAtMs >= 0 && now - it.endedAtMs >= SHOWN_AFTER_MS) ||
            (it.liftedAtMs >= 0 && now - it.liftedAtMs >= LOST_AFTER_MS) ||
            (it.provisionalSinceMs >= 0 && now - it.provisionalSinceMs >= UNCONFIRMED_MS)
    }

    private fun startTicking() {
        if (ticking) return
        ticking = true
        Choreographer.getInstance().postFrameCallback(tick)
    }

    /** Draws what every contact still needs, if anything changed. */
    private fun render() {
        val layer = layer ?: return
        val now = SystemClock.uptimeMillis()
        val upTo = shownUpTo(now)
        prune(now)
        val inks = ArrayList<WetInkLayer.Ink>(contacts.size)
        val bounds = RectF()
        var newest = 0L
        for (c in contacts) {
            val ink = c.ink(upTo) ?: continue
            inks.add(ink)
            WetInkLayer.addBounds(bounds, ink.hulls, AA_MARGIN)
            WetInkLayer.addBounds(bounds, ink.tip, AA_MARGIN)
            newest = maxOf(newest, c.newestNs)
        }
        if (inks.size == lastDrawn.size && inks.indices.all { inks[it] === lastDrawn[it] }) return
        lastDrawn = inks
        if (inks.isEmpty()) {
            if (shown) layer.clearSoon()
            shown = false
            return
        }
        layer.draw(WetInkLayer.Frame(bounds, inks, newest))
        shown = true
    }

    private var lastDrawn: List<WetInkLayer.Ink> = emptyList()

    private fun frameMs(): Double {
        val rate = host.flutterView()?.display?.refreshRate ?: 60f
        return 1000.0 / rate.coerceIn(30f, 240f)
    }

    /** A stroke's look, as `arm` and `begin` carry it (from index [from]). */
    private class Style(val color: Int, val radii: DoubleArray, val shape: WetInkShape, val clip: RectF) {
        companion object {
            fun of(message: List<*>, from: Int): Style? {
                val radii = message[from + 1] as DoubleArray
                val shape = WetInkShape.of(message[from + 2] as DoubleArray) ?: return null
                val c = message[from + 3] as DoubleArray
                if (radii.isEmpty() || c.size != 4) return null
                val clip = RectF(c[0].toFloat(), c[1].toFloat(), c[2].toFloat(), c[3].toFloat())
                return Style((message[from] as Number).toLong().toInt(), radii, shape, clip)
            }
        }
    }

    companion object {
        const val CHANNEL = "len/low_latency_ink"
        private const val TAG = "LenWetInk"

        /**
         * How long after Dart reports building a frame it is surely on
         * screen: raster, queued buffers, SurfaceFlinger's latch and the
         * present. Measured on a Galaxy Tab S8+ (120 Hz): 25 ms median,
         * 40 ms p99 (docs/INK_LAB.md, "Low-latency ink").
         */
        const val SHOWN_AFTER_MS = 50L

        /** An `arm` older than this (ms) is not trusted at pen-down. */
        private const val ARM_FRESH_MS = 400L

        /** A contact drawn from `arm` that Dart has not confirmed by then is dropped (ms). */
        private const val UNCONFIRMED_MS = 150L

        /** A lifted contact Dart has not ended by then is dropped (ms). */
        private const val LOST_AFTER_MS = 1000L

        /** Antialiasing reaches this far (px) past a shape. */
        private const val AA_MARGIN = 2f
    }
}
