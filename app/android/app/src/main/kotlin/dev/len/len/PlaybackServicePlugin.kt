package dev.len.len

import android.content.Context
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dart's side of [PlaybackService] on the `len/playback_service` channel
 * (`platform/media_controls_android.dart`):
 *
 * - `show {title, album, playing, positionMs, durationMs, rate}` starts
 *   the service or updates its session and notification (positions in the
 *   kept audio); answers false when it could not start.
 * - `hide` stops it (the player closed).
 *
 * The session's controls, audio focus changes and unplugged headphones
 * arrive in Dart as `event {action, positionMs?}` calls. No permission is
 * asked: media notifications are exempt from Android 13's notification
 * permission. Registered as an engine plugin by [MainActivity], so it is
 * torn down with the engine (stopping the service: nothing would play).
 */
class PlaybackServicePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL = "len/playback_service"
    }

    private var channel: MethodChannel? = null
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        PlaybackService.listener = { action, positionMs ->
            channel?.invokeMethod("event", mapOf("action" to action, "positionMs" to positionMs))
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        PlaybackService.listener = null
        stopService()
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "show" -> result.success(
                show(
                    NowPlaying(
                        call.argument<String>("title") ?: "",
                        call.argument<String>("album") ?: "",
                        call.argument<Boolean>("playing") ?: false,
                        (call.argument<Number>("positionMs") ?: 0).toLong(),
                        (call.argument<Number>("durationMs") ?: 0).toLong(),
                        (call.argument<Number>("rate") ?: 1).toFloat(),
                    ),
                ),
            )
            "hide" -> {
                stopService()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Stops the service; one created but not started yet ends once it is (see RecordingServicePlugin). */
    private fun stopService() {
        val service = PlaybackService.instance
        if (service != null && service.started) {
            service.finish()
        } else {
            PlaybackService.stopWhenStarted = true
        }
    }

    private fun show(now: NowPlaying): Boolean {
        PlaybackService.stopWhenStarted = false
        PlaybackService.instance?.let {
            it.update(now)
            return true
        }
        val context = context ?: return false
        val intent = PlaybackService.intentFor(context, now)
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            true
        } catch (e: RuntimeException) {
            Log.w("LenPlayback", "could not start the playback service", e)
            false
        }
    }
}
