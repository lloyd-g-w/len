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
        // Background audio recording (RecordingService.kt).
        flutterEngine.plugins.add(RecordingServicePlugin())
        // Background playback with media controls (PlaybackService.kt).
        flutterEngine.plugins.add(PlaybackServicePlugin())
        // ML Kit handwriting recognition off the UI thread.
        flutterEngine.plugins.add(HandwritingRecognitionPlugin())
        // "Save to device" for exports (system save dialogs).
        flutterEngine.plugins.add(SaveDocumentPlugin())
        // Print… (the system's print dialog for an exported PDF).
        flutterEngine.plugins.add(PrintPlugin())
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Cold start with files ("Open with" / "Share"). A recreated
        // activity has handled its intent already, and one started from
        // the recent apps gets the intent it was first started with again.
        val fromHistory = intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0
        if (savedInstanceState == null && !fromHistory) incoming?.handle(intent)
    }

    /** Whether Flutter has drawn its first frame (the splash screen is gone). */
    private var uiDisplayed = false

    override fun onStart() {
        super.onStart()
        if (uiDisplayed) wetInk?.attach()
    }

    /**
     * The low-latency layer (a surface of its own) is set up once Flutter's
     * first frame is up, not while the app starts: the splash screen stays
     * until that frame, and the layer is only needed for writing.
     */
    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        uiDisplayed = true
        wetInk?.attach()
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

    /**
     * Back with nothing left to pop (Flutter's `SystemNavigator.pop`): move
     * Len to the back as Android 12+ does with launcher activities, instead
     * of FlutterActivity's `finish()`, which would destroy the engine — and
     * with it a recording going on in the background and the open notebook.
     * (With predictive back, Android 13+, the system does the same itself.)
     */
    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
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
                    if (ev.actionMasked == MotionEvent.ACTION_DOWN) wetInk?.attach()
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
