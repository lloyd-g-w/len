package dev.len.len

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Dart's side of [RecordingService] on the `len/recording_service`
 * channel (`android_keep_alive.dart`):
 *
 * - `prepare` asks once (Android 13+) for permission to post the
 *   recording notification; answers whether it may be shown. Refusing
 *   does not stop background recording (the notification then only shows
 *   in the system's task manager).
 * - `show {title, paused, elapsedMs}` starts the service or updates its
 *   notification; answers false when it could not start.
 * - `hide` stops it.
 * - `openAppSettings` opens Len's page in the system settings (to allow
 *   the microphone after it was refused); answers whether it opened.
 *
 * The notification's buttons arrive in Dart as `action` calls ("pause",
 * "resume", "stop", or "failed"). Registered as an engine plugin by
 * [MainActivity], so it is torn down with the engine (stopping the
 * service: nobody would be recording any more).
 */
class RecordingServicePlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener {

    companion object {
        private const val CHANNEL = "len/recording_service"
        private const val REQUEST_NOTIFICATIONS = 0x4c45
        private const val PREFS = "len_recording"
        private const val ASKED = "askedNotifications"
    }

    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var activity: ActivityPluginBinding? = null
    private var pendingPermission: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        RecordingService.listener = { action -> channel?.invokeMethod("action", action) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        RecordingService.listener = null
        RecordingService.instance?.finish()
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> prepare(result)
            "show" -> result.success(
                show(
                    call.argument<String>("title") ?: "",
                    call.argument<Boolean>("paused") ?: false,
                    (call.argument<Number>("elapsedMs") ?: 0).toLong(),
                ),
            )
            "hide" -> {
                val service = RecordingService.instance
                if (service != null) service.finish() else RecordingService.stopWhenStarted = true
                result.success(null)
            }
            "openAppSettings" -> result.success(openAppSettings())
            else -> result.notImplemented()
        }
    }

    private fun openAppSettings(): Boolean {
        val context = context ?: return false
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", context.packageName, null),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            true
        } catch (e: RuntimeException) {
            Log.w("Len", "app settings unavailable", e)
            false
        }
    }

    private fun show(title: String, paused: Boolean, elapsedMs: Long): Boolean {
        RecordingService.stopWhenStarted = false
        RecordingService.instance?.let {
            it.update(title, paused, elapsedMs)
            return true
        }
        val context = context ?: return false
        val intent = Intent(context, RecordingService::class.java)
            .setAction(RecordingService.ACTION_START)
            .putExtra(RecordingService.EXTRA_TITLE, title)
            .putExtra(RecordingService.EXTRA_PAUSED, paused)
            .putExtra(RecordingService.EXTRA_ELAPSED, elapsedMs)
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            true
        } catch (e: RuntimeException) {
            Log.w("LenRecording", "could not start the recording service", e)
            false
        }
    }

    /** Android 13+: asks for POST_NOTIFICATIONS once per installation. */
    private fun prepare(result: MethodChannel.Result) {
        val context = context
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || context == null) {
            result.success(true)
            return
        }
        val permission = Manifest.permission.POST_NOTIFICATIONS
        if (context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val activity: Activity? = activity?.activity
        if (activity == null || pendingPermission != null || prefs.getBoolean(ASKED, false)) {
            result.success(false)
            return
        }
        prefs.edit().putBoolean(ASKED, true).apply()
        pendingPermission = result
        activity.requestPermissions(arrayOf(permission), REQUEST_NOTIFICATIONS)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_NOTIFICATIONS) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermission?.success(granted)
        pendingPermission = null
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activity?.removeRequestPermissionsResultListener(this)
        activity = null
        // A request without an activity to answer it: carry on without.
        pendingPermission?.success(false)
        pendingPermission = null
    }
}
