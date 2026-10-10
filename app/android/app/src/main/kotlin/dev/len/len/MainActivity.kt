package dev.len.len

import android.util.Log
import android.view.MotionEvent
import android.view.View
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var stylus: StylusCapture? = null
    private val location = IntArray(2)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        stylus = StylusCapture(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        stylus = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** Sees every touch first; forwards dense stylus samples, then lets Flutter have the event. */
    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        val capture = stylus
        if (capture != null) {
            try {
                val view = findViewById<View>(FLUTTER_VIEW_ID)
                if (view != null) {
                    view.getLocationInWindow(location)
                    capture.capture(ev, -location[0].toFloat(), -location[1].toFloat())
                }
            } catch (e: RuntimeException) {
                // Dense samples are a refinement; never let them break input.
                Log.w("Len", "stylus capture failed", e)
            }
        }
        return super.dispatchTouchEvent(ev)
    }
}
