package dev.len.len

/**
 * The plain decisions of [PlaybackService], without Android types so they
 * run in the JVM unit tests (`tool/wet_ink_check/unit_test.sh`): what an
 * audio focus change or a media key means for Dart (`MediaEvent` in
 * `platform/media_controls_api.dart`), and what the media session shows.
 *
 * The constants mirror `android.media.AudioManager` and
 * `android.view.KeyEvent` (stable platform values).
 */
object PlaybackEvents {
    const val AUDIOFOCUS_GAIN = 1
    const val AUDIOFOCUS_LOSS = -1
    const val AUDIOFOCUS_LOSS_TRANSIENT = -2
    const val AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK = -3

    const val KEYCODE_MEDIA_NEXT = 87
    const val KEYCODE_MEDIA_PREVIOUS = 88
    const val KEYCODE_MEDIA_REWIND = 89
    const val KEYCODE_MEDIA_FAST_FORWARD = 90

    /** Custom actions of the session (Android 13+ media controls) and notification buttons. */
    const val FORWARD = "forward"
    const val REWIND = "rewind"
    const val STOP = "stop"

    /**
     * What an audio focus change asks of Dart: another app took the audio
     * for good ("focusLoss": pause), for a while — a call, an assistant —
     * ("focusLossTransient": pause, resume on "focusGain"), or only wants
     * it quieter ("duck"; Android 8+ ducks by itself and doesn't say).
     */
    fun focusChange(change: Int): String? = when (change) {
        AUDIOFOCUS_GAIN -> "focusGain"
        AUDIOFOCUS_LOSS -> "focusLoss"
        AUDIOFOCUS_LOSS_TRANSIENT -> "focusLossTransient"
        AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> "duck"
        else -> null
    }

    /**
     * Media keys the session doesn't map itself: a headset's next /
     * previous (and fast forward / rewind) skip 10 s in a lecture, there is
     * no next track. Null: the session's default handling (play / pause,
     * headset hook, stop).
     */
    fun mediaKey(keyCode: Int): String? = when (keyCode) {
        KEYCODE_MEDIA_NEXT, KEYCODE_MEDIA_FAST_FORWARD -> FORWARD
        KEYCODE_MEDIA_PREVIOUS, KEYCODE_MEDIA_REWIND -> REWIND
        else -> null
    }

    /** A position inside the kept audio, `0…durationMs`. */
    fun clampPosition(positionMs: Long, durationMs: Long): Long =
        positionMs.coerceIn(0L, maxOf(0L, durationMs))
}

/** What the session shows: the open recording ([title]) of a notebook ([album]). */
data class NowPlaying(
    val title: String,
    val album: String,
    val playing: Boolean,
    val positionMs: Long,
    val durationMs: Long,
    val rate: Float,
) {
    /** Notification text: the recording, else the notebook, else Len. */
    val heading: String get() = title.ifEmpty { album.ifEmpty { "Len" } }
}
