package dev.len.len

import android.content.Context
import android.util.Log
import android.view.MotionEvent
import android.view.PointerIcon
import android.widget.FrameLayout
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec

/**
 * Hides the system's stylus hover pointer (the S Pen's dot, Android 14+'s
 * stylus pointer) while Dart says a canvas draws its own hover preview
 * under the pen (`lib/ink/input/stylus_pointer.dart`, `true` / `false` on
 * `len/stylus_pointer`). Mice keep Flutter's own cursor.
 *
 * Flutter's cursor (`SystemMouseCursors.none` → `View.setPointerIcon`)
 * misses the stylus: `View.onResolvePointerIcon` hands the view's icon to
 * mouse devices only. So the Flutter view sits in this frame, which
 * answers a stylus or eraser pointer with `TYPE_NULL` while [hidden], and
 * defers to the view (null: the system's own stylus pointer) otherwise.
 * On Samsung's One UI, which keeps a per-tool icon on views
 * (`View.semSetPointerIcon(toolType, icon)`), that one is set too, if the
 * method is there: once hidden, restored with null (else One UI's
 * `SEM_TYPE_STYLUS_DEFAULT`). Over anything but a previewing canvas Dart
 * says false, so the pointer shows as usual there.
 */
class StylusPointerFrame(context: Context) : FrameLayout(context) {
    /** Whether a stylus hovering over the app shows no system pointer. */
    var hidden = false
        set(value) {
            if (field == value) return
            field = value
            samsung(value)
            // Re-resolve now (a tool picked while the pen rests).
            val icon = pointerIcon
            pointerIcon = icon
        }

    override fun onResolvePointerIcon(event: MotionEvent, pointerIndex: Int): PointerIcon? {
        if (StylusPointerRule.hides(hidden, event.getToolType(pointerIndex))) {
            return PointerIcon.getSystemIcon(context, PointerIcon.TYPE_NULL)
        }
        return super.onResolvePointerIcon(event, pointerIndex)
    }

    private var semSetPointerIcon = try {
        javaClass.getMethod("semSetPointerIcon", Int::class.javaPrimitiveType, PointerIcon::class.java)
    } catch (e: ReflectiveOperationException) {
        null
    } catch (e: RuntimeException) {
        null
    }

    private var semTouched = false

    private fun samsung(hide: Boolean) {
        val method = semSetPointerIcon ?: return
        if (!hide && !semTouched) return
        val icon = if (hide) PointerIcon.getSystemIcon(context, PointerIcon.TYPE_NULL) else null
        if (semSet(method, icon)) {
            semTouched = true
        } else if (!hide) {
            // No null accepted: One UI's own stylus pointer, by its type.
            val default = try {
                PointerIcon::class.java.getField("SEM_TYPE_STYLUS_DEFAULT").getInt(null)
            } catch (e: ReflectiveOperationException) {
                null
            }
            if (default != null) semSet(method, PointerIcon.getSystemIcon(context, default))
        }
    }

    private fun semSet(method: java.lang.reflect.Method, icon: PointerIcon?): Boolean = try {
        method.invoke(this, MotionEvent.TOOL_TYPE_STYLUS, icon)
        true
    } catch (e: ReflectiveOperationException) {
        Log.w("Len", "semSetPointerIcon failed", e)
        false
    } catch (e: RuntimeException) {
        Log.w("Len", "semSetPointerIcon failed", e)
        false
    }
}

/** Dart's `StylusPointer`: whether the canvas under the pen previews. */
class StylusPointerChannel(messenger: BinaryMessenger, frame: () -> StylusPointerFrame?) {
    private val channel = BasicMessageChannel(messenger, CHANNEL, StandardMessageCodec.INSTANCE)

    init {
        channel.setMessageHandler { message, reply ->
            frame()?.hidden = message == true
            reply.reply(null)
        }
    }

    fun dispose() = channel.setMessageHandler(null)

    companion object {
        const val CHANNEL = "len/stylus_pointer"
    }
}
