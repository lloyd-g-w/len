package dev.len.len

import android.os.Build
import android.view.MotionEvent
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryCodec
import io.flutter.plugin.common.BinaryMessenger
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Forwards every digitiser sample of stylus `MotionEvent`s to Dart.
 *
 * Android batches input: one `ACTION_MOVE` per frame carries all samples
 * since the previous one as *historical* samples (240+ Hz on an S Pen),
 * but Flutter's embedding forwards only the newest. This sends the whole
 * batch, as one binary message (`StylusBatchCodec` in
 * `lib/ink/input/stylus_batch.dart`), before Flutter sees the event; the
 * event itself is not consumed.
 */
class StylusCapture(messenger: BinaryMessenger) {
    private val channel = BasicMessageChannel(messenger, CHANNEL, BinaryCodec.INSTANCE)

    /** Event time of each pointer id's down event (Flutter's down `timeStamp`). */
    private val downTimes = LongArray(MAX_POINTER_ID + 1)

    /**
     * When pointer [pointerId] of [event] touched down: its own (pointer)
     * down event, which is what Flutter reports — not the gesture's first
     * down, `MotionEvent.getDownTime`.
     */
    fun downTimeOf(event: MotionEvent, pointerId: Int): Long =
        if (pointerId in downTimes.indices && downTimes[pointerId] != 0L) {
            downTimes[pointerId]
        } else {
            event.downTime
        }

    /**
     * Sends the stylus samples of [event] (window coordinates), shifted by
     * ([dx], [dy]) into the Flutter view's coordinates.
     */
    fun capture(event: MotionEvent, dx: Float, dy: Float) {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val id = event.getPointerId(event.actionIndex)
                if (id in downTimes.indices) downTimes[id] = event.eventTime
                return
            }
            MotionEvent.ACTION_MOVE, MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {}
            else -> return
        }
        val history = event.historySize
        if (history == 0) return // Flutter receives the only sample itself.
        var pointers = 0
        for (p in 0 until event.pointerCount) if (isStylus(event, p)) pointers++
        if (pointers == 0) return

        val samples = history + 1
        val size = HEADER_BYTES + pointers * (BATCH_BYTES + samples * SAMPLE_BYTES)
        val buffer = ByteBuffer.allocateDirect(size).order(ByteOrder.LITTLE_ENDIAN)
        buffer.putInt(VERSION).putInt(pointers)
        val eventUs = event.eventTime * 1000.0 // Flutter's PointerEvent.timeStamp
        for (p in 0 until event.pointerCount) {
            if (!isStylus(event, p)) continue
            val device = deviceOf(event, p)
            val downUs = downTimeOf(event, event.getPointerId(p)) * 1000.0
            buffer.putInt(device).putInt(samples).putDouble(downUs).putDouble(eventUs)
            for (h in 0 until history) {
                buffer.putDouble(historicalTimeUs(event, h))
                buffer.putFloat(event.getHistoricalX(p, h) + dx)
                buffer.putFloat(event.getHistoricalY(p, h) + dy)
                buffer.putFloat(event.getHistoricalPressure(p, h))
                buffer.putFloat(event.getHistoricalAxisValue(MotionEvent.AXIS_TILT, p, h))
                buffer.putFloat(event.getHistoricalAxisValue(MotionEvent.AXIS_ORIENTATION, p, h))
            }
            buffer.putDouble(currentTimeUs(event))
            buffer.putFloat(event.getX(p) + dx)
            buffer.putFloat(event.getY(p) + dy)
            buffer.putFloat(event.getPressure(p))
            buffer.putFloat(event.getAxisValue(MotionEvent.AXIS_TILT, p))
            buffer.putFloat(event.getAxisValue(MotionEvent.AXIS_ORIENTATION, p))
        }
        channel.send(buffer)
    }

    companion object {
        const val CHANNEL = "len/stylus_samples"
        private const val VERSION = 1
        private const val HEADER_BYTES = 8
        private const val BATCH_BYTES = 24
        private const val SAMPLE_BYTES = 28
        private const val MAX_POINTER_ID = 31

        /** Flutter's `PointerEvent.device` (AndroidTouchProcessor.uniquePointerIdByType). */
        fun deviceOf(event: MotionEvent, pointer: Int): Int =
            (event.getPointerId(pointer) shl 3) or (event.getToolType(pointer) and 7)

        fun isStylus(event: MotionEvent, pointer: Int): Boolean {
            val type = event.getToolType(pointer)
            return type == MotionEvent.TOOL_TYPE_STYLUS || type == MotionEvent.TOOL_TYPE_ERASER
        }

        fun historicalTimeUs(event: MotionEvent, h: Int): Double =
            if (Build.VERSION.SDK_INT >= 34) {
                event.getHistoricalEventTimeNanos(h) / 1000.0
            } else {
                event.getHistoricalEventTime(h) * 1000.0
            }

        fun currentTimeUs(event: MotionEvent): Double =
            if (Build.VERSION.SDK_INT >= 34) event.eventTimeNanos / 1000.0 else event.eventTime * 1000.0
    }
}
