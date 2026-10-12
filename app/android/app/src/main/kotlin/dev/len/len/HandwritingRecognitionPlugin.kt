package dev.len.len

import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognition
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognitionModel
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognitionModelIdentifier
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognizer
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognizerOptions
import com.google.mlkit.vision.digitalink.recognition.Ink
import com.google.mlkit.vision.digitalink.recognition.RecognitionContext
import com.google.mlkit.vision.digitalink.recognition.WritingArea
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Handwriting recognition with ML Kit Digital Ink, off the UI thread
 * (channel `len/handwriting`; Dart side: `MlKitRecognizer` in
 * `platform/handwriting_recognizer_native.dart`).
 *
 * The UI and platform threads are merged in Flutter on Android, so nothing
 * here may run there: the channel decodes its messages on a background
 * task queue, and the ink is built, recognised and answered on a
 * single-thread executor (which also owns [recognizers]). Points arrive packed in
 * typed arrays (`xs`, `ys` float32, `ts` int64 ms, `ends` = the end index
 * of each stroke) rather than one map per point.
 *
 * Model downloads stay with the `google_mlkit_digital_ink_recognition`
 * plugin, which only does them on request.
 */
class HandwritingRecognitionPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var executor: ExecutorService? = null

    /** Recognisers by language tag; only touched on the executor. */
    private val recognizers = HashMap<String, DigitalInkRecognizer>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = binding.binaryMessenger
        executor = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "len-handwriting").apply { isDaemon = true }
        }
        channel = MethodChannel(
            messenger,
            "len/handwriting",
            StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue(),
        ).also { it.setMethodCallHandler(this) }
    }

    /** Stops answering; recognisers are closed on the executor. */
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        executor?.let {
            it.execute { closeRecognizers() }
            it.shutdown()
        }
        executor = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val executor = executor
        if (executor == null) {
            result.error("detached", "the engine is going away", null)
            return
        }
        when (call.method) {
            "recognize" -> executor.execute { recognize(call, result, executor) }
            "close" -> executor.execute {
                closeRecognizers()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun recognize(call: MethodCall, result: MethodChannel.Result, executor: ExecutorService) {
        val ink: Ink
        val recognizer: DigitalInkRecognizer
        val context: RecognitionContext
        try {
            val language = call.argument<String>("language")!!
            recognizer = recognizers[language] ?: DigitalInkRecognition.getClient(
                DigitalInkRecognizerOptions.builder(model(language)).build(),
            ).also { recognizers[language] = it }
            ink = buildInk(
                call.argument<FloatArray>("xs")!!,
                call.argument<FloatArray>("ys")!!,
                call.argument<LongArray>("ts")!!,
                call.argument<IntArray>("ends")!!,
            )
            context = buildContext(call)
        } catch (e: Exception) {
            result.error("invalid_args", e.toString(), null)
            return
        }
        // ML Kit recognises on its own threads; the answer comes back here.
        recognizer.recognize(ink, context).addOnCompleteListener(executor) { task ->
            val error = task.exception
            if (error != null || !task.isSuccessful) {
                result.error("recognition_failed", error?.toString() ?: "cancelled", null)
                return@addOnCompleteListener
            }
            result.success(
                task.result.candidates.map { c ->
                    mapOf("text" to c.text, "score" to (c.score?.toDouble() ?: 0.0))
                },
            )
        }
    }

    private fun closeRecognizers() {
        for (r in recognizers.values) r.close()
        recognizers.clear()
    }

    companion object {
        private fun model(language: String): DigitalInkRecognitionModel {
            val id = DigitalInkRecognitionModelIdentifier.fromLanguageTag(language)
                ?: throw IllegalArgumentException("no handwriting model for $language")
            return DigitalInkRecognitionModel.builder(id).build()
        }

        private fun buildInk(xs: FloatArray, ys: FloatArray, ts: LongArray, ends: IntArray): Ink {
            require(xs.size == ys.size && xs.size == ts.size) { "point arrays differ in length" }
            val ink = Ink.builder()
            var start = 0
            for (end in ends) {
                require(end in start..xs.size) { "bad stroke end $end" }
                val stroke = Ink.Stroke.builder()
                for (i in start until end) stroke.addPoint(Ink.Point.create(xs[i], ys[i], ts[i]))
                ink.addStroke(stroke.build())
                start = end
            }
            return ink.build()
        }

        private fun buildContext(call: MethodCall): RecognitionContext {
            val builder = RecognitionContext.builder()
                .setPreContext(call.argument<String>("preContext") ?: "")
            val width = call.argument<Double>("width")
            val height = call.argument<Double>("height")
            if (width != null && height != null && width > 0 && height > 0) {
                builder.setWritingArea(WritingArea(width.toFloat(), height.toFloat()))
            }
            return builder.build()
        }
    }
}
