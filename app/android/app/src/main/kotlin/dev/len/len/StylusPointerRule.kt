package dev.len.len

/**
 * The plain-JVM half of [StylusPointerFrame], unit tested without Android:
 * which pointers get no system pointer while Dart says a canvas previews
 * under the pen. Only the stylus and its eraser end; mice keep Flutter's
 * own cursor, which already hides over a preview.
 */
object StylusPointerRule {
    /** `MotionEvent.TOOL_TYPE_STYLUS` and `TOOL_TYPE_ERASER` (Android's values). */
    const val TOOL_TYPE_STYLUS = 2
    const val TOOL_TYPE_ERASER = 4

    /** Whether a pointer of [toolType] gets no system pointer while [hidden]. */
    fun hides(hidden: Boolean, toolType: Int): Boolean =
        hidden && (toolType == TOOL_TYPE_STYLUS || toolType == TOOL_TYPE_ERASER)
}
