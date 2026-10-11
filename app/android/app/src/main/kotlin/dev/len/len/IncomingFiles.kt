package dev.len.len

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/**
 * "Open with Len" (`ACTION_VIEW`) and "Share to Len" (`ACTION_SEND`,
 * `ACTION_SEND_MULTIPLE`) of PDFs and images.
 *
 * The content URIs are only readable while the granting intent is alive,
 * so each one is copied right away (off the main thread) into
 * `cache/incoming/<random>/<display name>`; Dart (`incoming_files_native.dart`)
 * then gets a `files` call with `[{path, name, mime}]` on the
 * `len/incoming_files` channel and imports the copies into the app's
 * own storage. Batches wait until Dart has called `ready` (a cold start
 * delivers the launch intent's files before the UI is up). The copies
 * are deleted when the next engine starts.
 */
class IncomingFiles(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val pending = mutableListOf<List<Map<String, String?>>>()
    private var ready = false
    private var disposed = false
    private val dir = File(context.cacheDir, "incoming")

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "ready") {
                ready = true
                pending.forEach(::send)
                pending.clear()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        // Copies from the previous run were imported (or abandoned) by now.
        io.execute { dir.deleteRecursively() }
    }

    /** Copies the files [intent] carries, if any, and hands them to Dart. */
    fun handle(intent: Intent?) {
        val uris = urisOf(intent ?: return)
        if (uris.isEmpty()) return
        val fallbackMime = intent.type
        io.execute {
            val files = uris.mapNotNull { copy(it, fallbackMime) }
            main.post {
                if (disposed || files.isEmpty()) return@post
                if (ready) send(files) else pending.add(files)
            }
        }
    }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        io.shutdown()
    }

    private fun send(files: List<Map<String, String?>>) = channel.invokeMethod("files", files)

    private fun urisOf(intent: Intent): List<Uri> = when (intent.action) {
        Intent.ACTION_VIEW -> listOfNotNull(intent.data)
        Intent.ACTION_SEND -> listOfNotNull(stream(intent))
        Intent.ACTION_SEND_MULTIPLE -> streams(intent)
        else -> emptyList()
    }

    @Suppress("DEPRECATION")
    private fun stream(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    @Suppress("DEPRECATION")
    private fun streams(intent: Intent): List<Uri> =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        }.orEmpty().filterNotNull()

    /** Copies [uri] into the cache; null (logged) if it can't be read. */
    private fun copy(uri: Uri, fallbackMime: String?): Map<String, String?>? = try {
        val resolver = context.contentResolver
        val mime = resolver.getType(uri) ?: fallbackMime?.takeUnless { it.endsWith("/*") }
        val name = safeName(displayName(resolver, uri) ?: uri.lastPathSegment ?: "file")
        val target = File(File(dir, UUID.randomUUID().toString()), name)
        target.parentFile?.mkdirs()
        val input = if (uri.scheme == ContentResolver.SCHEME_FILE) {
            File(uri.path ?: throw IllegalArgumentException("no path")).inputStream()
        } else {
            resolver.openInputStream(uri) ?: throw IllegalStateException("no stream")
        }
        input.use { from -> target.outputStream().use { to -> from.copyTo(to) } }
        mapOf("path" to target.absolutePath, "name" to name, "mime" to mime)
    } catch (e: Exception) {
        // SecurityException (no permission), IOException, …: skip this one.
        Log.w("Len", "Couldn't read incoming file $uri", e)
        null
    }

    private fun displayName(resolver: ContentResolver, uri: Uri): String? {
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) return null
        return try {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst() && !it.isNull(0)) it.getString(0) else null
            }
        } catch (e: Exception) {
            null
        }
    }

    /** A file name without path separators (names come from other apps). */
    private fun safeName(name: String): String {
        val clean = name.substringAfterLast('/').replace(Regex("[\\\\:*?\"<>|\\x00-\\x1f]"), "_")
        return clean.trim().trimStart('.').ifEmpty { "file" }.takeLast(120)
    }

    companion object {
        const val CHANNEL = "len/incoming_files"
    }
}
