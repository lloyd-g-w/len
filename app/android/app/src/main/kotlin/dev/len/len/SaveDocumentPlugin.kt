package dev.len.len

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File

/**
 * "Save to device" for exports on the `len/save_document` channel
 * (`platform/file_export_native.dart`):
 *
 * - `save {paths, names, mime}` copies already written files to where the
 *   user picks with the system's dialogs: one file through "create
 *   document" (the user may rename it), several into a folder chosen with
 *   "open document tree". Answers the name of the saved file or folder,
 *   or null if cancelled; fails with `save_failed` when writing fails.
 */
class SaveDocumentPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener {

    companion object {
        private const val CHANNEL = "len/save_document"
        private const val REQUEST_FILE = 0x4c53
        private const val REQUEST_FOLDER = 0x4c54
    }

    private class Pending(
        val paths: List<String>,
        val names: List<String>,
        val mime: String,
        val result: MethodChannel.Result,
    )

    private var channel: MethodChannel? = null
    private var activity: ActivityPluginBinding? = null
    private var pending: Pending? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "save") {
            result.notImplemented()
            return
        }
        val paths = call.argument<List<String>>("paths") ?: emptyList()
        val names = call.argument<List<String>>("names") ?: emptyList()
        val host: Activity? = activity?.activity
        if (paths.isEmpty() || paths.size != names.size || host == null || pending != null) {
            result.error("save_failed", "Cannot save now", null)
            return
        }
        // "audio/*" and the like are not valid types for a new document.
        val mime = (call.argument<String>("mime") ?: "").let {
            if (it.isEmpty() || it.contains('*')) "application/octet-stream" else it
        }
        pending = Pending(paths, names, mime, result)
        try {
            if (paths.size == 1) {
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType(mime)
                    .putExtra(Intent.EXTRA_TITLE, names[0])
                host.startActivityForResult(intent, REQUEST_FILE)
            } else {
                host.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), REQUEST_FOLDER)
            }
        } catch (e: RuntimeException) {
            pending = null
            result.error("save_failed", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_FILE && requestCode != REQUEST_FOLDER) return false
        val request = pending ?: return true
        pending = null
        val uri = data?.data
        val resolver = activity?.activity?.contentResolver
        if (resultCode != Activity.RESULT_OK || uri == null || resolver == null) {
            request.result.success(null)
            return true
        }
        // Copying may take a while (large PDFs): off the main thread.
        Thread {
            try {
                val name = if (requestCode == REQUEST_FILE) {
                    copy(resolver, request.paths[0], uri)
                    displayName(resolver, uri) ?: request.names[0]
                } else {
                    saveAll(resolver, request, uri)
                }
                main.post { request.result.success(name) }
            } catch (e: Exception) {
                Log.w("LenSave", "saving failed", e)
                main.post { request.result.error("save_failed", e.message, null) }
            }
        }.start()
        return true
    }

    /** Creates every file of [request] in folder [tree]; its name. */
    private fun saveAll(resolver: ContentResolver, request: Pending, tree: Uri): String? {
        val folder = DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        for (i in request.paths.indices) {
            val target = DocumentsContract.createDocument(
                resolver,
                folder,
                request.mime,
                request.names[i],
            ) ?: throw IllegalStateException("Cannot create ${request.names[i]}")
            copy(resolver, request.paths[i], target)
        }
        return displayName(resolver, folder)
    }

    private fun copy(resolver: ContentResolver, path: String, target: Uri) {
        // "wt" truncates a file picked to be replaced; some providers (cloud
        // drives) only know "w", fine for the new, empty documents they make.
        val out = try {
            resolver.openOutputStream(target, "wt")
        } catch (e: java.io.FileNotFoundException) {
            resolver.openOutputStream(target, "w")
        } catch (e: IllegalArgumentException) {
            resolver.openOutputStream(target, "w")
        } ?: throw IllegalStateException("Cannot write $target")
        out.use { sink -> File(path).inputStream().use { it.copyTo(sink) } }
    }

    private fun displayName(resolver: ContentResolver, uri: Uri): String? = try {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }
    } catch (e: RuntimeException) {
        null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addActivityResultListener(this)
    }

    /** The system dialog may still answer the recreated activity: [pending] stays. */
    override fun onDetachedFromActivityForConfigChanges() {
        activity?.removeActivityResultListener(this)
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    /** No activity left to answer: Dart's `save` ends as cancelled, not never. */
    override fun onDetachedFromActivity() {
        onDetachedFromActivityForConfigChanges()
        pending?.result?.success(null)
        pending = null
    }
}
