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
 * it, with a short predicted tip ([WetInkTip], [WetInkPrediction]).
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
 * on screen for sure ([WetInkHandover]).
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

    // Flutter's frame reports (`progress`): when the overlay may let go.
    private val handover = WetInkHandover()

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
                    contact.onRetract = retractLog()
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
                // The pen-up's frame draws no tip at all (see WetContact.tipOf).
                contact.predicted(
                    if (up || !contact.predicts) 0
                    else tip?.predict(
                        event.getPointerId(p), event.eventTime, dx, dy,
                        contact.predictionMs, contact.rawPrediction,
                    ) ?: 0,
                )
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
                contact.onRetract = retractLog()
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
                handover.frameMs = frameMs()
                handover.report(now, upTo, (message.getOrNull(2) as? Number)?.toLong() ?: -1)
            }
            "end" -> contacts.find { it.matches(message[1], message[2]) }?.let {
                // Sent right after the report of the frame that shows it.
                it.endedAt = handover.latest
                it.commit((message.getOrNull(3) as? Number)?.toDouble() ?: 0.0)
            }
            "cancel" -> contacts.find { it.matches(message[1], message[2]) }?.let {
                contacts.remove(it)
                if (it === current) current = null
                render()
            }
            "log" -> logging = message.getOrNull(1) == true
        }
        if (contacts.isNotEmpty()) startTicking()
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
        // Shown by Flutter for sure, or never answered by Dart (it went away).
        val gone = handover.releases(now, it.endedAt, it.liftedAtMs, it.provisionalSinceMs)
        if (gone && logging) logPruned(it, now)
        gone
    }

    // The flicker log (`FlickerLog` in Dart, docs/INK_LAB.md): only while
    // Dart asks for it (`log`), the overlay tells it when it let go of ink.
    private var logging = false

    private fun send(vararg values: Any?) = channel.send(values.toList())

    /** Each Flutter frame report the overlay lets go of (its ink is drawn no more). */
    private val released = { _: Double, frameId: Long ->
        if (frameId >= 0) send("released", frameId, SystemClock.uptimeMillis())
    }

    private fun retractLog(): ((Double) -> Unit)? {
        if (!logging) return null
        return { px -> if (px > RETRACT_LOG_PX) send("retract", px, SystemClock.uptimeMillis()) }
    }

    private fun logPruned(c: WetContact, now: Long) {
        val how = when {
            c.endedAt >= 0 -> "shown"
            c.provisionalSinceMs >= 0 -> "unanswered"
            else -> "lost"
        }
        send("pruned", c.device, c.downMs * 1000.0, now, how, c.sampleCount, handover.frameIdOf(c.endedAt))
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
        val upTo = handover.shownUpTo(now, if (logging) released else null)
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

        /** An `arm` older than this (ms) is not trusted at pen-down. */
        private const val ARM_FRESH_MS = 400L

        /** A predicted tip taken back further (px) is logged (`FlickerLog.retractLimitPx`). */
        private const val RETRACT_LOG_PX = 0.5

        /** Antialiasing reaches this far (px) past a shape. */
        private const val AA_MARGIN = 2f
    }
}
