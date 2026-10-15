package dev.len.len

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.ceil

/**
 * The overlay's hand-over timing ([WetInkHandover]) against a simulated
 * Flutter pipeline: the UI thread builds a frame per vsync while there is
 * input (or trailing frames), only into a free slot of the two-deep frame
 * pipeline, and reports it; the raster thread takes frames one at a time;
 * a rasterised frame is latched at the next vsync and presented at the one
 * after. At every millisecond the overlay may only have let go of input
 * that a presented Flutter frame shows — else that ink is on neither layer
 * for a while: a flicker.
 */
class WetInkHandoverTest {
    @Test
    fun steadyFramesHandOverAfterTheMeasuredDelay() {
        val run = Pipeline().run()
        assertEquals("ms of gap", 0, run.gapMs)
        // No later than before: 70 ms after the report (plus a tick).
        assertTrue("held ${run.worstHoldMs} ms", run.worstHoldMs <= WetInkHandover.SHOWN_AFTER_MS + 9)
        assertTrue("released the ended stroke", run.releasedAtMs >= 0)
    }

    @Test
    fun aRasterStallMidStrokeOpensNoGap() {
        // One frame takes 120 ms to rasterise (a busy page, tile renders).
        val run = Pipeline(rasterMs = { k, _ -> if (k == 20) 120.0 else 4.0 }).run()
        assertEquals("ms of gap", 0, run.gapMs)
    }

    @Test
    fun slowRasterThroughoutOpensNoGap() {
        // Every frame rasterises in 30 ms: Flutter at a quarter of the rate.
        val run = Pipeline(rasterMs = { _, _ -> 30.0 }).run()
        assertEquals("ms of gap", 0, run.gapMs)
    }

    @Test
    fun aRasterStallAtPenUpKeepsTheStrokeUntilItsFrameShows() {
        // The frame with the committed stroke rasterises late.
        val run = Pipeline(rasterMs = { _, ended -> if (ended) 110.0 else 4.0 }).run()
        assertEquals("ms of gap", 0, run.gapMs)
        assertTrue("released", run.releasedAtMs >= 0)
        assertTrue(
            "released at ${run.releasedAtMs}, committed frame shown at ${run.endShownAtMs}",
            run.releasedAtMs >= run.endShownAtMs,
        )
    }

    @Test
    fun aBusyUiThreadAtPenDownKeepsTheArmedInk() {
        val h = WetInkHandover()
        // Drawn from `arm` at 0; Dart's `begin` comes 400 ms later (a long frame).
        for (t in 0L..400L) assertTrue("dropped at $t ms", !h.releases(t, -1, -1, 0))
        // Never answered at all: dropped in the end.
        assertTrue(h.releases(WetInkHandover.LOST_AFTER_MS, -1, -1, 0))
    }

    @Test
    fun reportsThatStopAreReleasedInTheEnd() {
        val h = WetInkHandover()
        h.report(0, 10.0)
        assertTrue(!h.isShown(0, 500))
        assertTrue(h.isShown(0, WetInkHandover.LOST_AFTER_MS))
    }

    /**
     * A stroke written from 0 to [strokeMs] (input every 4 ms), the
     * pen-up's frame committing it; [rasterMs] gives a frame's raster time
     * (its index, and whether it is the committed stroke's).
     */
    private class Pipeline(
        val strokeMs: Double = 400.0,
        val rasterMs: (Int, Boolean) -> Double = { _, _ -> 4.0 },
        val buildMs: Long = 3,
    ) {
        class Frame(val k: Int, val upTo: Double, val ended: Boolean) {
            var rasterDone = Double.POSITIVE_INFINITY

            /** Latched at the vsync after its raster, shown at the next. */
            val presented get() = (ceil(rasterDone / VSYNC) + 1) * VSYNC
        }

        class Result(val gapMs: Int, val worstHoldMs: Long, val releasedAtMs: Long, val endShownAtMs: Long)

        fun run(): Result {
            val h = WetInkHandover().also { it.frameMs = VSYNC }
            val frames = ArrayList<Frame>()
            val queue = ArrayDeque<Frame>() // Built, not yet taken by the raster thread.
            val reports = ArrayList<Pair<Long, Frame>>() // Due at, frame.
            val arrived = HashMap<Long, Long>()
            var rasterFreeAt = 0.0
            var trailing = 0
            var builtUpTo = -1.0
            var ended = -1L
            var endFrame: Frame? = null
            var released = -1L
            var gap = 0
            var worstHold = 0L
            var nextVsync = 0.0
            for (t in 0L until (strokeMs + 1500).toLong()) {
                val now = t.toDouble()
                // The raster thread takes the next frame when free.
                while (queue.isNotEmpty() && rasterFreeAt <= now) {
                    val f = queue.removeFirst()
                    f.rasterDone = now + rasterMs(f.k, f.ended)
                    rasterFreeAt = f.rasterDone
                }
                // The UI thread builds a frame at each vsync while there is
                // something to show, into a free pipeline slot.
                if (now >= nextVsync) {
                    nextVsync += VSYNC
                    val input = minOf(now - now % 4.0, strokeMs)
                    val newInput = input > builtUpTo
                    val penUp = now > strokeMs && endFrame == null
                    if ((newInput || trailing > 0 || penUp) && queue.size < 2) {
                        val f = Frame(frames.size, input, penUp)
                        frames.add(f)
                        queue.addLast(f)
                        reports.add(Pair(t + buildMs, f)) // The post-frame callback.
                        builtUpTo = input
                        trailing = if (newInput || penUp) TRAILING else trailing - 1
                        if (penUp) endFrame = f
                    }
                }
                val due = reports.filter { it.first <= t }
                reports.removeAll(due)
                for ((_, f) in due) {
                    h.report(t, f.upTo, f.k.toLong())
                    arrived[f.k.toLong()] = t
                    if (f.ended) ended = h.latest
                }
                // What Flutter shows now, and from where the overlay draws.
                val flutterUpTo = frames.lastOrNull { it.presented <= now }?.upTo ?: -1.0
                val overlayFrom = h.shownUpTo(t) { upTo, id ->
                    // While writing (the trailing frames after the lift wait for none).
                    if (upTo < strokeMs) worstHold = maxOf(worstHold, t - arrived[id]!!)
                }
                if (released < 0) {
                    // Input between the two is on neither layer.
                    if (overlayFrom > flutterUpTo) gap++
                    if (ended >= 0 && h.releases(t, ended, -1, -1)) released = t
                }
            }
            val endShown = endFrame?.presented?.toLong() ?: -1
            // Released before the committed stroke's frame showed: gone meanwhile.
            if (released in 0 until endShown) gap += (endShown - released).toInt()
            return Result(gap, worstHold, released, endShown)
        }

        companion object {
            const val VSYNC = 1000.0 / 120
            const val TRAILING = 3
        }
    }
}
