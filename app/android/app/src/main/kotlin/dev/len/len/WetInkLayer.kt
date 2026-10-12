package dev.len.len

import android.graphics.BlendMode
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RectF
import android.os.Trace
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import androidx.annotation.RequiresApi
import androidx.graphics.lowlatency.CanvasFrontBufferedRenderer

/**
 * The surface of the low-latency ink: a translucent [SurfaceView] above the
 * Flutter view (same bounds), drawn only through the **front buffer** of a
 * [CanvasFrontBufferedRenderer] — the buffer the display is scanning out — so
 * a [Frame] shows as soon as its few draw calls finish, with no buffer swap
 * and no wait for the next vsync or SurfaceFlinger's next composition.
 *
 * Each [Frame] is the whole overlay: its [Frame.dirty] rectangle (what the
 * previous frame and this one cover) is cleared and the ink redrawn, so ink
 * can also be taken away (the predicted tip, the tail Flutter has caught up
 * with). The multi-buffered layer is never used; [clear] hides and clears
 * the front buffer.
 */
@RequiresApi(29)
internal class WetInkLayer(parent: ViewGroup, above: View) {
    /**
     * One stroke's ink: (x, y, radius) triples of the hulls to fill and of
     * the predicted tip, drawn only inside [clip].
     */
    class Ink(val color: Int, val clip: RectF, val hulls: FloatArray, val tip: FloatArray)

    /** Everything the overlay shows. [newestNs] is the newest input it contains (for traces). */
    class Frame(val dirty: RectF, val inks: List<Ink>, val newestNs: Long)

    private val view = SurfaceView(parent.context)
    private val paint = Paint().apply {
        isAntiAlias = true
        style = Paint.Style.FILL
    }
    private val path = Path()
    private val renderer: CanvasFrontBufferedRenderer<Frame>

    init {
        view.setZOrderMediaOverlay(true)
        view.holder.setFormat(PixelFormat.TRANSLUCENT)
        view.isClickable = false
        view.isFocusable = false
        view.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        val size = ViewGroup.LayoutParams.MATCH_PARENT
        parent.addView(view, parent.indexOfChild(above) + 1, ViewGroup.LayoutParams(size, size))
        renderer = CanvasFrontBufferedRenderer(view, Callback())
    }

    /** Whether the layer still sits above [flutter] (activity views get recreated). */
    fun isAbove(flutter: View): Boolean = view.parent != null && view.parent === flutter.parent

    /** Shows [frame] (from the main thread; rendered on the renderer's thread). */
    fun draw(frame: Frame) = renderer.renderFrontBufferedLayer(frame)

    /** Removes all ink. */
    fun clear() = renderer.cancel()

    fun release() {
        renderer.release(true)
        (view.parent as? ViewGroup)?.removeView(view)
    }

    private inner class Callback : CanvasFrontBufferedRenderer.Callback<Frame> {
        override fun onDrawFrontBufferedLayer(canvas: Canvas, bufferWidth: Int, bufferHeight: Int, param: Frame) {
            val traced = Trace.isEnabled()
            if (traced) Trace.beginSection("len.wet ${param.newestNs}")
            canvas.save()
            canvas.clipRect(param.dirty)
            canvas.drawColor(Color.TRANSPARENT, BlendMode.CLEAR)
            for (ink in param.inks) {
                canvas.save()
                canvas.clipRect(ink.clip)
                paint.color = ink.color
                path.rewind()
                addHulls(path, ink.hulls)
                addHulls(path, ink.tip)
                canvas.drawPath(path, paint)
                canvas.restore()
            }
            canvas.restore()
            if (traced) Trace.endSection()
        }

        override fun onDrawMultiBufferedLayer(
            canvas: Canvas,
            bufferWidth: Int,
            bufferHeight: Int,
            params: Collection<Frame>,
        ) {
            canvas.drawColor(Color.TRANSPARENT, BlendMode.CLEAR)
        }
    }

    companion object {
        /**
         * Adds the ink of consecutive (x, y, radius) triples to [path]: each
         * pair is the hull of its two circles (a tapered capsule), one triple
         * a dot. Every piece winds the same way, so filling the path (non-zero
         * rule) covers their union once: antialiased edges are not darkened
         * by pieces overlapping, as they would be if each were filled alone.
         */
        fun addHulls(path: Path, xyr: FloatArray) {
            val n = xyr.size / 3
            if (n == 0) return
            path.addCircle(xyr[0], xyr[1], xyr[2], Path.Direction.CW)
            for (i in 1 until n) {
                val o = i * 3
                val ax = xyr[o - 3]
                val ay = xyr[o - 2]
                val ra = xyr[o - 1]
                val bx = xyr[o]
                val by = xyr[o + 1]
                val rb = xyr[o + 2]
                path.addCircle(bx, by, rb, Path.Direction.CW)
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
                // a+n1 → b+n1 → b+n2 → a+n2 turns clockwise on screen (y down),
                // as `Path.Direction.CW` circles do.
                path.moveTo(ax + ra * n2x, ay + ra * n2y)
                path.lineTo(bx + rb * n2x, by + rb * n2y)
                path.lineTo(bx + rb * n1x, by + rb * n1y)
                path.lineTo(ax + ra * n1x, ay + ra * n1y)
                path.close()
            }
        }

        /** Grows [out] to hold every circle of [xyr], plus [margin]. */
        fun addBounds(out: RectF, xyr: FloatArray, margin: Float) {
            for (i in 0 until xyr.size / 3) {
                val x = xyr[i * 3]
                val y = xyr[i * 3 + 1]
                val r = xyr[i * 3 + 2] + margin
                if (out.isEmpty) out.set(x - r, y - r, x + r, y + r) else out.union(x - r, y - r, x + r, y + r)
            }
        }
    }
}
