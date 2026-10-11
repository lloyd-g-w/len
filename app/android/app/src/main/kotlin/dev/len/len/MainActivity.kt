package dev.len.len

import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.view.MotionEvent
import android.view.View
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity(), WetInkOverlay.Host {
    private var stylus: StylusCapture? = null
    private var wetInk: WetInkOverlay? = null
    private var incoming: IncomingFiles? = null
    private val location = IntArray(2)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        stylus = StylusCapture(messenger)
        wetInk = WetInkOverlay(this, messenger)
        incoming = IncomingFiles(applicationContext, messenger)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Cold start with files ("Open with" / "Share"); a recreated
        // activity has handled its intent already.
        if (savedInstanceState == null) incoming?.handle(intent)
    }

    /** Warm start: files opened with / shared to the running app. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        incoming?.handle(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        stylus = null
        wetInk?.dispose()
        wetInk = null
        incoming?.dispose()
        incoming = null
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
