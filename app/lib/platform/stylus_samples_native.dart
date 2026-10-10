import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../ink/input/sample_source.dart';
import '../ink/input/stylus_batch.dart';
import '../ink/input/wet_ink.dart';

/// Channel carrying `StylusBatchCodec` messages from `StylusCapture.kt`.
const String stylusSamplesChannel = 'len/stylus_samples';

/// Control messages for the native low-latency ink overlay (`WetInkOverlay.kt`).
const String lowLatencyInkChannel = 'len/low_latency_ink';

StylusBatchBuffer? _buffer;

/// A sample source for one input controller, or null where the platform
/// already delivers every sample (everything but Android).
///
/// [wetInk], when given, is asked at the start of each stylus stroke whether
/// low-latency ink is on (null = off) and how the stroke looks; the native
/// overlay then draws its tip ahead of Flutter.
SampleSource? openStylusSamples({WetInkStyle? Function()? wetInk, bool Function()? lowLatency}) {
  if (!Platform.isAndroid) return null;
  final buffer = _buffer ??= _listen();
  final merger = StylusSampleMerger(buffer, devicePixelRatio: _devicePixelRatio);
  if (wetInk == null || lowLatency == null) return merger;
  return _LowLatencySource(merger, wetInk, lowLatency);
}

double _devicePixelRatio() =>
    WidgetsBinding.instance.platformDispatcher.implicitView?.devicePixelRatio ?? 1;

/// Starts receiving batches into one app-wide buffer.
StylusBatchBuffer _listen() {
  final buffer = StylusBatchBuffer();
  const BasicMessageChannel<ByteData?>(stylusSamplesChannel, BinaryCodec()).setMessageHandler((
    message,
  ) async {
    if (message != null) buffer.addAll(StylusBatchCodec.decode(message));
    return null;
  });
  return buffer;
}

const _overlay = BasicMessageChannel<Object?>(lowLatencyInkChannel, StandardMessageCodec());
bool? _overlayEnabled;

/// Tells the overlay which contact to draw and how far Flutter has got.
///
/// Messages: `[enable, bool]`, `[begin, device, downTimeUs, argb, radii px]`,
/// `[progress, eventTimeUs]` (after a frame showing input up to that event
/// was built), `[end, device, downTimeUs]` (after the frame that shows the
/// finished stroke).
class _LowLatencySource implements SampleSource {
  _LowLatencySource(this._inner, this._style, this._enabled);

  final SampleSource _inner;
  final WetInkStyle? Function() _style;
  final bool Function() _enabled;

  PointerDownEvent? _contact;
  bool _drawing = false;
  int _processedUs = 0;
  bool _progressScheduled = false;

  @override
  void begin(PointerDownEvent down) {
    _inner.begin(down);
    final enabled = _enabled();
    if (enabled != _overlayEnabled) {
      _overlayEnabled = enabled;
      _send(['enable', enabled]);
    }
    final stylus = down.kind == PointerDeviceKind.stylus;
    _contact = enabled && stylus ? down : null;
    _drawing = false;
  }

  @override
  List<PointerSample> between(PointerEvent event) {
    final samples = _inner.between(event);
    final contact = _contact;
    if (contact == null || event.device != contact.device) return samples;
    final style = _style();
    if (!_drawing && style != null) {
      _drawing = true;
      final dpr = _devicePixelRatio();
      _send([
        'begin',
        contact.device,
        contact.timeStamp.inMicroseconds.toDouble(),
        style.color,
        Float64List.fromList([for (final r in style.radii) r * dpr]),
      ]);
    } else if (_drawing && style == null) {
      _finish(); // Straightened (or no longer ink): Flutter draws it.
      _contact = null;
      return samples;
    }
    _processedUs = event.timeStamp.inMicroseconds;
    _scheduleProgress();
    return samples;
  }

  @override
  void end() {
    _inner.end();
    _finish();
    _contact = null;
  }

  void _finish() {
    final contact = _contact;
    if (!_drawing || contact == null) return;
    _drawing = false;
    final message = ['end', contact.device, contact.timeStamp.inMicroseconds.toDouble()];
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _send(message))
      ..ensureVisualUpdate();
  }

  void _scheduleProgress() {
    if (_progressScheduled) return;
    _progressScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _progressScheduled = false;
      if (_drawing) _send(['progress', _processedUs.toDouble()]);
    });
  }

  static void _send(List<Object?> message) => _overlay.send(message).ignore();
}
