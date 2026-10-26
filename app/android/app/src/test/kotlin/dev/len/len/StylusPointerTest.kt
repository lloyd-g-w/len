package dev.len.len

import dev.len.len.StylusPointerRule.TOOL_TYPE_ERASER
import dev.len.len.StylusPointerRule.TOOL_TYPE_STYLUS
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StylusPointerTest {
    // MotionEvent's TOOL_TYPE_FINGER and TOOL_TYPE_MOUSE.
    private val finger = 1
    private val mouse = 3

    @Test
    fun hidesTheStylusAndItsEraserEndWhileHidden() {
        assertTrue(StylusPointerRule.hides(true, TOOL_TYPE_STYLUS))
        assertTrue(StylusPointerRule.hides(true, TOOL_TYPE_ERASER))
    }

    @Test
    fun leavesMiceAndFingersToFlutter() {
        assertFalse(StylusPointerRule.hides(true, mouse))
        assertFalse(StylusPointerRule.hides(true, finger))
    }

    @Test
    fun showsTheStylusOtherwise() {
        assertFalse(StylusPointerRule.hides(false, TOOL_TYPE_STYLUS))
        assertFalse(StylusPointerRule.hides(false, TOOL_TYPE_ERASER))
    }
}
