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
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import android.view.KeyEvent

/**
 * Keeps a recording playing while Len is in the background (screen off,
 * another app in front): a foreground service of type "mediaPlayback"
 * with a platform media session — the lock screen's and the system's
 * media controls, Bluetooth / headset buttons — and a media notification
 * (recording, notebook; back 10 s, play / pause, forward 10 s, stop).
 * Audio focus and unplugged headphones: [PlaybackFocus].
 *
 * The audio itself stays in Dart (`PlaybackController` and the
 * `audioplayers` plugin, in this process); this service holds the process
 * foreground (and a partial wake lock while playing) and forwards every
 * control to Dart through [listener] ([PlaybackServicePlugin]), which
 * answers with the new state ([update]). Started when a recording first
 * plays (Len in front, as Android 12+ requires), stopped when the player
 * closes, when the engine goes away or when Len's task is removed.
 */
class PlaybackService : Service() {
    companion object {
        private const val TAG = "LenPlayback"
        private const val CHANNEL_ID = "playback"
        private const val NOTIFICATION_ID = 0x4c4550
        const val ACTION_START = "dev.len.len.playback.START"
        private const val ACTION_PREFIX = "dev.len.len.playback."
        const val EXTRA_TITLE = "title"
        const val EXTRA_ALBUM = "album"
        const val EXTRA_PLAYING = "playing"
        const val EXTRA_POSITION = "positionMs"
        const val EXTRA_DURATION = "durationMs"
        const val EXTRA_RATE = "rate"

        /** The running service (main thread only). */
        var instance: PlaybackService? = null
            private set

        /**
         * Receives "play", "pause", "forward", "rewind", "stop", "seek"
         * (with a position in the kept audio), the focus events of
         * [PlaybackEvents.focusChange], "noisy", and "failed" (it could not
         * go to the foreground). Null without an engine.
         */
        var listener: ((String, Long?) -> Unit)? = null

        /** Set when Dart hides before a just-started service is up (see RecordingService). */
        var stopWhenStarted = false

        fun intentFor(context: Context, now: NowPlaying): Intent =
            Intent(context, PlaybackService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_TITLE, now.title)
                .putExtra(EXTRA_ALBUM, now.album)
                .putExtra(EXTRA_PLAYING, now.playing)
                .putExtra(EXTRA_POSITION, now.positionMs)
                .putExtra(EXTRA_DURATION, now.durationMs)
                .putExtra(EXTRA_RATE, now.rate)
    }

    private var now = NowPlaying("", "", false, 0L, 0L, 1f)
    private var foreground = false

    /** Whether [onStartCommand] ran: until then, stopping must wait (see [stopWhenStarted]). */
    var started = false
        private set
    private lateinit var session: MediaSession
    private lateinit var focus: PlaybackFocus
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        focus = PlaybackFocus(this) { forward(it) }
        session = MediaSession(this, "Len").apply {
            @Suppress("DEPRECATION")
            setFlags(
                MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS,
            )
            setCallback(callback)
            setSessionActivity(openApp())
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        started = true
        val action = intent?.action
        if (action != null && action != ACTION_START && action.startsWith(ACTION_PREFIX)) {
            forward(action.removePrefix(ACTION_PREFIX))
        } else {
            update(
                NowPlaying(
                    intent?.getStringExtra(EXTRA_TITLE) ?: "",
                    intent?.getStringExtra(EXTRA_ALBUM) ?: "",
                    intent?.getBooleanExtra(EXTRA_PLAYING, false) ?: false,
                    intent?.getLongExtra(EXTRA_POSITION, 0L) ?: 0L,
                    intent?.getLongExtra(EXTRA_DURATION, 0L) ?: 0L,
                    intent?.getFloatExtra(EXTRA_RATE, 1f) ?: 1f,
                ),
            )
            if (stopWhenStarted) {
                stopWhenStarted = false
                finish()
            }
        }
        // Never restarted by the system: the player lives in Dart.
        return START_NOT_STICKY
    }

    /** Shows (going foreground the first time) or refreshes the session and notification. */
    fun update(now: NowPlaying) {
        this.now = now
        session.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, now.heading)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, now.album)
                .putString(MediaMetadata.METADATA_KEY_ALBUM, now.album)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, now.durationMs)
                .build(),
        )
        session.setPlaybackState(state())
        session.isActive = true
        focus.playing(now.playing)
        holdWakeLock(now.playing)
        val notification = build()
        if (foreground) {
            notifications().notify(NOTIFICATION_ID, notification)
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            foreground = true
        } catch (e: RuntimeException) {
            // Android 12+: not allowed from the background. Playback goes on in front.
            Log.w(TAG, "could not start the foreground service", e)
            listener?.invoke("failed", null)
            finish()
        }
    }

    /** Ends the service, the session and the notification (player closed). */
    fun finish() {
        focus.release()
        holdWakeLock(false)
        session.isActive = false
        if (foreground) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            foreground = false
        }
        stopSelf()
    }

    private fun forward(action: String, positionMs: Long? = null) {
        val target = listener
        if (target == null) {
            // Nobody left to play (the engine is gone): just go away.
            finish()
            return
        }
        target(action, positionMs)
    }

    /** Len was swiped away from the recent apps: playback ends with it. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        listener?.invoke(PlaybackEvents.STOP, null)
        finish()
    }

    override fun onDestroy() {
        focus.release()
        holdWakeLock(false)
        session.release()
        if (instance === this) instance = null
        super.onDestroy()
    }

    private val callback = object : MediaSession.Callback() {
        override fun onPlay() = forward("play")
        override fun onPause() = forward("pause")
        override fun onStop() = forward(PlaybackEvents.STOP)
        override fun onSeekTo(pos: Long) = forward("seek", pos)
        override fun onFastForward() = forward(PlaybackEvents.FORWARD)
        override fun onRewind() = forward(PlaybackEvents.REWIND)
        override fun onSkipToNext() = forward(PlaybackEvents.FORWARD)
        override fun onSkipToPrevious() = forward(PlaybackEvents.REWIND)
        override fun onCustomAction(action: String, extras: android.os.Bundle?) = forward(action)

        override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
            val key = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                mediaButtonIntent.getParcelableExtra(Intent.EXTRA_KEY_EVENT, KeyEvent::class.java)
            } else {
                @Suppress("DEPRECATION")
                mediaButtonIntent.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
            }
            val skip = key?.let { PlaybackEvents.mediaKey(it.keyCode) }
                ?: return super.onMediaButtonEvent(mediaButtonIntent)
            if (key.action == KeyEvent.ACTION_DOWN && key.repeatCount == 0) forward(skip)
            return true
        }
    }

    private fun state(): PlaybackState = PlaybackState.Builder()
        .setActions(
            PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_SEEK_TO or
                PlaybackState.ACTION_STOP or PlaybackState.ACTION_FAST_FORWARD or
                PlaybackState.ACTION_REWIND,
        )
        .setState(
            if (now.playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
            PlaybackEvents.clampPosition(now.positionMs, now.durationMs),
            now.rate,
            SystemClock.elapsedRealtime(),
        )
        // Android 13+ media controls: the slots beside play / pause.
        .addCustomAction(custom(PlaybackEvents.REWIND, "Back 10 s", R.drawable.ic_media_replay_10))
        .addCustomAction(custom(PlaybackEvents.FORWARD, "Forward 10 s", R.drawable.ic_media_forward_10))
        .addCustomAction(custom(PlaybackEvents.STOP, "Stop", R.drawable.ic_media_close))
        .build()

    private fun custom(action: String, label: String, icon: Int) =
        PlaybackState.CustomAction.Builder(action, label, icon).build()

    /** The CPU keeps running with the screen off while playing (Dart follows the position). */
    private fun holdWakeLock(hold: Boolean) {
        if (!hold) {
            wakeLock?.let { if (it.isHeld) it.release() }
            wakeLock = null
            return
        }
        if (wakeLock != null) return
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Len:playback").apply {
            setReferenceCounted(false)
            // Upper bound (a lecture day); released on pause.
            acquire(12 * 60 * 60 * 1000L)
        }
    }

    private fun notifications() =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    /** Android 12 and older show these buttons; 13+ takes them from the session. */
    private fun build(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ensureChannel()
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_LOW)
        }
        builder
            .setSmallIcon(R.drawable.ic_stat_playback)
            .setContentTitle(now.heading)
            .setContentText(now.album)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(openApp())
            .setDeleteIntent(serviceAction(PlaybackEvents.STOP))
            .addAction(action(R.drawable.ic_media_replay_10, "Back 10 s", PlaybackEvents.REWIND))
            .addAction(
                if (now.playing) {
                    action(R.drawable.ic_media_pause, "Pause", "pause")
                } else {
                    action(R.drawable.ic_media_play, "Play", "play")
                },
            )
            .addAction(action(R.drawable.ic_media_forward_10, "Forward 10 s", PlaybackEvents.FORWARD))
            .addAction(action(R.drawable.ic_media_close, "Stop", PlaybackEvents.STOP))
            .setStyle(
                Notification.MediaStyle()
                    .setMediaSession(session.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2),
            )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = notifications()
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(CHANNEL_ID, "Playback", NotificationManager.IMPORTANCE_LOW)
        channel.description = "Shown while Len plays a recording"
        channel.setShowBadge(false)
        manager.createNotificationChannel(channel)
    }

    private fun serviceAction(name: String): PendingIntent {
        val intent = Intent(this, PlaybackService::class.java).setAction(ACTION_PREFIX + name)
        return PendingIntent.getService(
            this,
            name.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun action(icon: Int, label: String, name: String): Notification.Action =
        Notification.Action.Builder(Icon.createWithResource(this, icon), label, serviceAction(name))
            .build()

    /** Tapping the notification brings Len (singleTask) back to the front. */
    private fun openApp(): PendingIntent? {
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            this,
            1,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
