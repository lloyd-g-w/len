package dev.len.len

import android.util.Log
import android.view.MotionEvent
import android.view.View
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity(), WetInkOverlay.Host {
    private var stylus: StylusCapture? = null
    private var wetInk: WetInkOverlay? = null
    private val location = IntArray(2)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        stylus = StylusCapture(messenger)
        wetInk = WetInkOverlay(this, messenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        stylus = null
        wetInk?.dispose()
        wetInk = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun flutterView(): View? = findViewById(FLUTTER_VIEW_ID)

    /**
     * Sees every touch first: forwards dense stylus samples (and feeds the
     * low-latency overlay), then lets Flutter have the event unchanged.
     */
    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        val capture = stylus
        if (capture != null) {
            try {
                val view = flutterView()
                if (view != null) {
                    view.getLocationInWindow(location)
                    val dx = -location[0].toFloat()
                    val dy = -location[1].toFloat()
                    capture.capture(ev, dx, dy)
                    wetInk?.onTouch(ev, dx, dy, capture)
                }
            } catch (e: RuntimeException) {
                // Dense samples are a refinement; never let them break input.
                Log.w("Len", "stylus capture failed", e)
            }
        }
        return super.dispatchTouchEvent(ev)
    }
}
