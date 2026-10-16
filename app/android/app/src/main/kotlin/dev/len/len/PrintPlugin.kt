package dev.len.len

import android.content.Context
import android.graphics.pdf.PdfRenderer
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Printing on the `len/print` channel (`platform/print_document_native.dart`):
 *
 * - `print {path, name, pages}` opens the system's print dialog for the PDF
 *   written at `path` (the job and document named `name`; `pages` is the
 *   page count should the PDF not be countable here). Answers once the
 *   dialog is open; the dialog and the print spooler take it from there.
 *   Fails with `print_failed` without an activity.
 */
class PrintPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var activity: ActivityPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "len/print").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "print") {
            result.notImplemented()
            return
        }
        val path = call.argument<String>("path")
        val name = call.argument<String>("name") ?: "Len"
        val pages = call.argument<Int>("pages") ?: PrintPages.UNKNOWN
        // PrintManager needs an activity's context (the dialog is one).
        val host = activity?.activity
        if (path == null || host == null) {
            result.error("print_failed", "Cannot print now", null)
            return
        }
        try {
            val manager = host.getSystemService(Context.PRINT_SERVICE) as PrintManager
            manager.print(name, PdfFileAdapter(File(path), name, pages), PrintAttributes.Builder().build())
            result.success(null)
        } catch (e: RuntimeException) {
            Log.w("LenPrint", "printing failed", e)
            result.error("print_failed", e.message, null)
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activity = null
    }
}

/**
 * Streams the PDF [file] to the print framework: the page count comes from
 * the PDF itself ([knownPages] if it can't be read), every write copies
 * the whole file (the spooler keeps only the pages chosen, see
 * [PrintPages]) off the main thread, and a cancelled layout or write says
 * so. The file's folder (one per print) is deleted when the dialog closes.
 */
private class PdfFileAdapter(
    private val file: File,
    private val name: String,
    private val knownPages: Int,
) : PrintDocumentAdapter() {
    private val main = Handler(Looper.getMainLooper())
    private var pageCount: Int? = null

    override fun onLayout(
        oldAttributes: PrintAttributes?,
        newAttributes: PrintAttributes,
        cancellationSignal: CancellationSignal,
        callback: LayoutResultCallback,
        extras: Bundle?,
    ) {
        if (cancellationSignal.isCanceled) {
            callback.onLayoutCancelled()
            return
        }
        if (!file.isFile) {
            callback.onLayoutFailed("The PDF to print is gone")
            return
        }
        // The PDF's pages don't change with the paper or printer chosen:
        // only the first layout changes the content.
        val first = pageCount == null
        val count = pageCount ?: countPages().also { pageCount = it }
        val info = PrintDocumentInfo.Builder(name)
            .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
            .setPageCount(count)
            .build()
        callback.onLayoutFinished(info, first)
    }

    /** The PDF's page count, else [knownPages]. */
    private fun countPages(): Int = try {
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
            val renderer = PdfRenderer(fd)
            try {
                renderer.pageCount
            } finally {
                renderer.close()
            }
        }
    } catch (e: Exception) {
        Log.w("LenPrint", "cannot count the pages of $file", e)
        if (knownPages > 0) knownPages else PrintPages.UNKNOWN
    }

    override fun onWrite(
        pages: Array<out PageRange>,
        destination: ParcelFileDescriptor,
        cancellationSignal: CancellationSignal,
        callback: WriteResultCallback,
    ) {
        val count = pageCount ?: PrintPages.UNKNOWN
        if (PrintPages.requested(pages.map { it.start..it.end }, count) == null) {
            callback.onWriteFailed("No such pages")
            return
        }
        Thread {
            val outcome = try {
                val done = file.inputStream().use { input ->
                    FileOutputStream(destination.fileDescriptor).use { output ->
                        PrintPages.copyUnlessCancelled(input, output, { cancellationSignal.isCanceled })
                    }
                }
                if (done) WriteOutcome.Written else WriteOutcome.Cancelled
            } catch (e: Exception) {
                Log.w("LenPrint", "writing $file failed", e)
                WriteOutcome.Failed(e.message)
            }
            main.post {
                when (outcome) {
                    WriteOutcome.Written -> callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
                    WriteOutcome.Cancelled -> callback.onWriteCancelled()
                    is WriteOutcome.Failed -> callback.onWriteFailed(outcome.message)
                }
            }
        }.start()
    }

    override fun onFinish() {
        file.parentFile?.deleteRecursively()
    }

    private sealed interface WriteOutcome {
        object Written : WriteOutcome
        object Cancelled : WriteOutcome
        data class Failed(val message: String?) : WriteOutcome
    }
}
