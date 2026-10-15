package dev.len.len

/**
 * When the low-latency overlay may let go of ink because Flutter's own
 * frame shows it (pure Kotlin, so the JVM tests can drive it through a
 * simulated Flutter pipeline: `WetInkHandoverTest`).
 *
 * Dart reports every frame it builds while there is overlay ink
 * ([report]: the newest input the frame contains), and keeps reporting a
 * few frames after the last input ([TRAILING_FRAMES] in
 * `low_latency_ink_native.dart`). A frame's ink is surely on screen once
 *
 *  * [SHOWN_AFTER_MS] have passed since its report (build → present was
 *    measured at 48 ms at most on a Galaxy Tab S8+), **and**
 *  * a frame built [PIPELINE_FRAMES] frames later has been reported and
 *    two display frames more have passed: Flutter builds a frame only
 *    once a slot of its two-deep frame pipeline is free, so that frame's
 *    report means the raster thread has finished this one; then the
 *    buffer still waits for SurfaceFlinger's latch and the present.
 *
 * The time alone opened gaps when Flutter's raster thread fell behind (a
 * busy page, tile renders, a busy CPU): the overlay let go of ink whose
 * frame was not on screen yet, and the newest ink vanished for a few
 * frames and came back — a flicker. A frame stall holds the reports back,
 * so the second rule waits for it. [LOST_AFTER_MS] bounds the wait if
 * reports stop (the app going away).
 */
internal class WetInkHandover {
    // The arrival time (ms) of report n at [n % RING], the input it shows
    // and Dart's frame id; [count] reports so far.
    private val arrivedMs = LongArray(RING)
    private val upToMs = DoubleArray(RING)
    private val frameIds = LongArray(RING)
    var count = 0L
        private set

    // The newest report known to be on screen, and its input.
    private var shown = -1L
    private var shownUpTo = Double.NEGATIVE_INFINITY

    /** Display frame interval (ms). */
    var frameMs = 1000.0 / 120

    /** Dart built a frame with input up to [upTo] (ms), at [nowMs]; its id [frameId]. */
    fun report(nowMs: Long, upTo: Double, frameId: Long = -1) {
        val i = (count % RING).toInt()
        arrivedMs[i] = nowMs
        upToMs[i] = upTo
        frameIds[i] = frameId
        count++
    }

    /** The newest report so far (-1: none). */
    val latest get() = count - 1

    /** Whether report [n]'s frame is surely on screen at [nowMs]. */
    fun isShown(n: Long, nowMs: Long): Boolean {
        if (n < 0) return true
        if (n >= count) return false
        if (n < count - RING + PIPELINE_FRAMES) return true // Hundreds of frames ago.
        val at = arrivedMs[(n % RING).toInt()]
        if (nowMs - at < SHOWN_AFTER_MS) return false
        if (nowMs - at >= LOST_AFTER_MS) return true
        val later = n + PIPELINE_FRAMES
        return later < count && nowMs - arrivedMs[(later % RING).toInt()] >= settleMs
    }

    /** After the frame [PIPELINE_FRAMES] later: latch and present. */
    private val settleMs get() = 2 * frameMs + 2

    /**
     * Input time (ms) of the newest frame surely on screen at [nowMs]
     * (−∞: none); [onShown] hears of each report that became so, in
     * order (its input and Dart's frame id).
     */
    fun shownUpTo(nowMs: Long, onShown: ((Double, Long) -> Unit)? = null): Double {
        while (shown + 1 < count && isShown(shown + 1, nowMs)) {
            shown++
            val i = (shown % RING).toInt()
            shownUpTo = upToMs[i]
            onShown?.invoke(upToMs[i], frameIds[i])
        }
        return shownUpTo
    }

    /**
     * Whether a contact's ink may go at [nowMs]: ended in report [endedAt]
     * (−1: not ended) that is on screen, lifted at [liftedAtMs] and never
     * ended by Dart, or drawn from `arm` since [provisionalSinceMs] and
     * never answered (−1: not so).
     */
    fun releases(nowMs: Long, endedAt: Long, liftedAtMs: Long, provisionalSinceMs: Long): Boolean =
        (endedAt >= 0 && isShown(endedAt, nowMs)) ||
            (liftedAtMs >= 0 && nowMs - liftedAtMs >= LOST_AFTER_MS) ||
            (provisionalSinceMs >= 0 && nowMs - provisionalSinceMs >= LOST_AFTER_MS)

    companion object {
        /**
         * How long after Dart reports building a frame it is on screen at
         * the earliest the overlay assumes: raster, queued buffers,
         * SurfaceFlinger's latch and the present. Measured on a Galaxy Tab
         * S8+ (120 Hz): 21 ms median, 41 ms p99, 48 ms at most
         * (docs/INK_LAB.md, "Low-latency ink").
         */
        const val SHOWN_AFTER_MS = 70L

        /**
         * Frames Flutter builds after one before that one has surely left
         * the raster thread (a two-deep pipeline, and the one rastering).
         */
        const val PIPELINE_FRAMES = 3

        /**
         * A contact Dart never answered (no `begin` or `skip` for a stylus
         * down drawn from `arm`, no `end` for a lift) goes after this long
         * (ms), as does a report no later frame follows. Dart answers every
         * stylus down as its UI thread gets to it, so only a stalled or
         * gone UI isolate takes this long; going sooner made the first ink
         * of a stroke vanish and come back when the UI thread was busy
         * (loading, a long frame) at pen-down.
         */
        const val LOST_AFTER_MS = 1000L

        private const val RING = 256
    }
}
