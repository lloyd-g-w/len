package dev.len.len

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build

/**
 * Audio focus and "becoming noisy" for [PlaybackService]: asks for the
 * audio when playback starts and reports to [onEvent] what Dart should do
 * (see [PlaybackEvents.focusChange]); while playing, headphones unplugged
 * (or a Bluetooth headset gone) report "noisy" (pause).
 *
 * The player itself (`audioplayers`) is told to leave focus alone
 * (`audioplayers_playback.dart`), so Dart's play / pause state is the only
 * one. Android 8+ ducks by itself (`setWillPauseWhenDucked(false)`).
 */
class PlaybackFocus(private val context: Context, private val onEvent: (String) -> Unit) {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var held = false
    private var request: AudioFocusRequest? = null
    private var listening = false

    private val listener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> held = true
            AudioManager.AUDIOFOCUS_LOSS, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> held = false
        }
        PlaybackEvents.focusChange(change)?.let(onEvent)
    }

    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) onEvent("noisy")
        }
    }

    /** Playback started or stopped: hold the audio and listen for unplugging while it plays. */
    fun playing(playing: Boolean) {
        if (!playing) {
            listenForNoisy(false)
            return
        }
        if (!held) requestFocus()
        if (held) listenForNoisy(true)
    }

    /** Gives the audio back (playback closed). */
    fun release() {
        listenForNoisy(false)
        if (!held && request == null) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            request?.let { audio.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audio.abandonAudioFocus(listener)
        }
        held = false
    }

    private fun requestFocus() {
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val focusRequest = request ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attributes)
                .setWillPauseWhenDucked(false)
                .setOnAudioFocusChangeListener(listener)
                .build()
                .also { request = it }
            audio.requestAudioFocus(focusRequest)
        } else {
            @Suppress("DEPRECATION")
            audio.requestAudioFocus(listener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        }
        held = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        // A call is going on: playing now would talk over it.
        if (!held) onEvent("focusLoss")
    }

    private fun listenForNoisy(on: Boolean) {
        if (on == listening) return
        listening = on
        if (on) {
            val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(noisy, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                context.registerReceiver(noisy, filter)
            }
        } else {
            context.unregisterReceiver(noisy)
        }
    }

    companion object {
        /** A lecture: spoken audio played as media (matches the player's). */
        val attributes: AudioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
    }
}
