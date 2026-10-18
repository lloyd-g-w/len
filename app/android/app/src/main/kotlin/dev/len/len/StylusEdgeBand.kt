package dev.len.len

/**
 * The plain-JVM half of [StylusEdgeGuard], unit tested without Android:
 * where the band kept free of the system's Back gesture lies while a
 * stylus is near, and when it is worth moving.
 *
 * The band is [bandPx] tall (Android honours at most 200 dp of exclusion
 * per edge), centred on the stylus's y and kept inside the view. It only
 * follows the stylus once it has moved more than [stepPx] from the y the
 * band was last placed at: setting exclusion rects costs a pass through
 * the system's window manager.
 */
class StylusEdgeBand(private val bandPx: Int, private val stepPx: Float) {
    /** Top of the band in view pixels; meaningless unless [placed]. */
    var top = 0
        private set

    /** Bottom of the band (exclusive) in view pixels. */
    var bottom = 0
        private set

    /** Whether there is a band. */
    var placed = false
        private set

    // The y the band was centred on, and the view's height then.
    private var centre = 0f
    private var height = 0

    /**
     * The stylus is at [y] in a view [viewHeight] pixels tall. Returns
     * whether the band moved (or appeared): the rects need setting.
     */
    fun follow(y: Float, viewHeight: Int): Boolean {
        if (viewHeight <= 0) return clear()
        if (placed && viewHeight == height && kotlin.math.abs(y - centre) <= stepPx) return false
        val band = minOf(bandPx, viewHeight)
        val t = (y - band / 2f).toInt().coerceIn(0, viewHeight - band)
        val moved = !placed || t != top || t + band != bottom
        centre = y
        height = viewHeight
        top = t
        bottom = t + band
        placed = true
        return moved
    }

    /** Drops the band; whether there was one (the rects need clearing). */
    fun clear(): Boolean {
        val was = placed
        placed = false
        return was
    }

    companion object {
        /** Android's cap on gesture exclusion per edge (dp). */
        const val BAND_DP = 200f

        /** How far (dp) the stylus moves before the band follows. */
        const val STEP_DP = 24f
    }
}
