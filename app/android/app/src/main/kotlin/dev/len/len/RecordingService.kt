package dev.len.len

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log

/**
 * Keeps an audio recording going while Len is in the background (screen
 * off, another app in front): a foreground service of type "microphone"
 * — without one Android hands backgrounded apps silence — showing an
 * ongoing notification with the time, Pause / Resume and Stop.
 *
 * The recording itself stays in Dart (`RecordingController` and the
 * `record` plugin, in this process); this service only keeps the process
 * foreground and a partial wake lock held, and forwards the
 * notification's buttons to Dart through [listener]
 * ([RecordingServicePlugin]). Started and updated by the plugin, stopped
 * when the recording is saved, when the engine goes away, or (with no one
 * left to save) when Len's task is removed.
 */
class RecordingService : Service() {
    companion object {
        private const val TAG = "LenRecording"
        const val CHANNEL_ID = "recording"
        private const val NOTIFICATION_ID = 0x4c454e
        const val ACTION_START = "dev.len.len.recording.START"
        const val ACTION_PAUSE = "dev.len.len.recording.PAUSE"
        const val ACTION_RESUME = "dev.len.len.recording.RESUME"
        const val ACTION_STOP = "dev.len.len.recording.STOP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_PAUSED = "paused"
        const val EXTRA_ELAPSED = "elapsedMs"

        /** The running service (main thread only). */
        var instance: RecordingService? = null
            private set

        /**
         * Receives "pause", "resume", "stop" (buttons) and "failed" (the
         * service could not go to the foreground). Null without an engine.
         */
        var listener: ((String) -> Unit)? = null

        /**
         * Set when Dart stops before a just-started service is up; the
         * service then goes foreground (as Android requires) and ends.
         */
        var stopWhenStarted = false

        /** How long a removed task gets to save before the service quits. */
        private const val SAVE_GRACE_MS = 8000L
    }

    private var title = ""
    private var paused = false
    private var elapsedMs = 0L
    private var foreground = false

    /** Whether [onStartCommand] ran: until then, stopping must wait (see [stopWhenStarted]). */
    var started = false
        private set
    private var wakeLock: PowerManager.WakeLock? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        started = true
        when (intent?.action) {
            ACTION_PAUSE -> forward("pause")
            ACTION_RESUME -> forward("resume")
            ACTION_STOP -> forward("stop")
            else -> {
                update(
                    intent?.getStringExtra(EXTRA_TITLE) ?: "",
                    intent?.getBooleanExtra(EXTRA_PAUSED, false) ?: false,
                    intent?.getLongExtra(EXTRA_ELAPSED, 0L) ?: 0L,
                )
                if (stopWhenStarted) {
                    stopWhenStarted = false
                    finish()
                }
            }
        }
        // Never restarted by the system: a recording cannot be resumed.
        return START_NOT_STICKY
    }

    /** Shows (going foreground the first time) or refreshes the notification. */
    fun update(title: String, paused: Boolean, elapsedMs: Long) {
        this.title = title
        this.paused = paused
        this.elapsedMs = elapsedMs
        val notification = build()
        if (foreground) {
            notifications().notify(NOTIFICATION_ID, notification)
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            foreground = true
            acquireWakeLock()
        } catch (e: RuntimeException) {
            // Android 12+: not allowed from the background; Android 14+:
            // microphone permission missing. Recording goes on in front.
            Log.w(TAG, "could not start the foreground service", e)
            listener?.invoke("failed")
            stopSelf()
        }
    }

    /** Ends the service and removes its notification (recording saved). */
    fun finish() {
        if (foreground) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            foreground = false
        }
        stopSelf()
    }

    private fun forward(action: String) {
        val target = listener
        if (target == null) {
            // Nobody left to record (the engine is gone): just go away.
            finish()
            return
        }
        target(action)
    }

    /**
     * Len was swiped away from the recent apps: ask Dart to stop and save
     * while the process still lives, and quit soon after in any case.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        listener?.invoke("stop")
        main.postDelayed({ if (instance === this) finish() }, SAVE_GRACE_MS)
    }

    override fun onDestroy() {
        main.removeCallbacksAndMessages(null)
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        if (instance === this) instance = null
        super.onDestroy()
    }

    /** The CPU keeps running with the screen off (audio encoding, Dart). */
    private fun acquireWakeLock() {
        if (wakeLock != null) return
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Len:recording").apply {
            setReferenceCounted(false)
            // Upper bound (a lecture day); released when recording stops.
            acquire(12 * 60 * 60 * 1000L)
        }
    }

    private fun notifications() =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun build(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ensureChannel()
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_LOW)
        }
        builder
            .setSmallIcon(R.drawable.ic_stat_recording)
            .setContentTitle(if (paused) "Recording paused" else "Recording")
            .setContentText(title.ifEmpty { "Len" })
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(openApp())
            .addAction(
                action(
                    if (paused) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause,
                    if (paused) "Resume" else "Pause",
                    if (paused) ACTION_RESUME else ACTION_PAUSE,
                ),
            )
            .addAction(action(android.R.drawable.ic_menu_close_clear_cancel, "Stop", ACTION_STOP))
        if (paused) {
            builder.setShowWhen(false).setSubText(clock(elapsedMs))
        } else {
            // A live "0:42" counting up from when the audio started.
            builder
                .setShowWhen(true)
                .setUsesChronometer(true)
                .setWhen(System.currentTimeMillis() - elapsedMs)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = notifications()
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(CHANNEL_ID, "Recording", NotificationManager.IMPORTANCE_LOW)
        channel.description = "Shown while Len records audio"
        channel.setShowBadge(false)
        manager.createNotificationChannel(channel)
    }

    private fun action(icon: Int, label: String, action: String): Notification.Action {
        val intent = Intent(this, RecordingService::class.java).setAction(action)
        val pending = PendingIntent.getService(
            this,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Action.Builder(Icon.createWithResource(this, icon), label, pending)
            .build()
    }

    /** Tapping the notification brings Len (singleTask) back to the front. */
    private fun openApp(): PendingIntent? {
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun clock(ms: Long): String {
        val total = ms / 1000
        val h = total / 3600
        val m = total % 3600 / 60
        val s = total % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
    }
}
