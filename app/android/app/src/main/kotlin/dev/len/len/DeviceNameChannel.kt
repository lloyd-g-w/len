package dev.len.len

import android.content.Context
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * `len/device` (`device_label_native.dart`): `name` answers the name the
 * user gave the device (Settings → About, e.g. "Galaxy Tab S9"), else its
 * maker and model ("samsung SM-X710" as "Samsung SM-X710"). Len suggests it
 * as this device's name to the user's other devices.
 */
object DeviceNameChannel {
    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, "len/device").setMethodCallHandler { call, result ->
            if (call.method == "name") result.success(name(context)) else result.notImplemented()
        }
    }

    private fun name(context: Context): String {
        val given = try {
            // Settings.Global.DEVICE_NAME (API 25), by name for older systems.
            Settings.Global.getString(context.contentResolver, "device_name")
        } catch (e: Exception) {
            null
        }
        if (!given.isNullOrBlank()) return given.trim()
        val maker = Build.MANUFACTURER.replaceFirstChar { it.uppercase() }
        val model = Build.MODEL
        return if (model.startsWith(maker, ignoreCase = true)) model else "$maker $model"
    }
}
