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
void Function(List<StylusBatch> batches)? _observer;

/// Lets the Ink Lab record every stylus batch as it arrives (null stops).
/// Batches only flow once [openStylusSamples] has been called (Android).
void observeStylusBatches(void Function(List<StylusBatch> batches)? observer) =>
    _observer = observer;

/// A sample source for one input controller, or null where the platform
/// already delivers every sample (everything but Android).
///
/// With [wetInk] and [wetInkView] (Android), the native low-latency overlay
/// draws the newest part of each stylus stroke ahead of Flutter: [wetInk]
/// says at the start of the stroke how it looks (null: the overlay cannot
/// draw it), [wetInkView] where it may be drawn.
SampleSource? openStylusSamples({
  WetInkStyle? Function()? wetInk,
  WetInkView Function()? wetInkView,
}) {
  if (!Platform.isAndroid) return null;
  final buffer = _buffer ??= _listen();
  final merger = StylusSampleMerger(buffer, devicePixelRatio: _devicePixelRatio);
  if (wetInk == null || wetInkView == null) return merger;
  return _LowLatencySource(merger, wetInk, wetInkView);
}

double _devicePixelRatio() =>
    WidgetsBinding.instance.platformDispatcher.implicitView?.devicePixelRatio ?? 1;

/// Starts receiving batches into one app-wide buffer.
StylusBatchBuffer _listen() {
  final buffer = StylusBatchBuffer();
  const BasicMessageChannel<ByteData?>(stylusSamplesChannel, BinaryCodec()).setMessageHandler((
    message,
  ) async {
    if (message == null) return null;
    final batches = StylusBatchCodec.decode(message);
    buffer.addAll(batches);
    _observer?.call(batches);
    return null;
  });
  return buffer;
}

const _overlay = BasicMessageChannel<Object?>(lowLatencyInkChannel, StandardMessageCodec());

/// Tells the overlay which contact to draw and how far Flutter has got.
///
/// Messages: `[begin, device, downTimeUs, argb, radii px, shape
/// (`WetInkShape.toList`, px), clip [l, t, r, b] px]` (at pen-down: ink
/// shows from there), `[progress, eventTimeUs]` (after a frame showing
/// input up to that event was built), `[end, device, downTimeUs]` (after
/// the frame that shows the finished stroke), `[cancel, device,
/// downTimeUs]` (the overlay's ink is no longer right: remove it now).
/// Pixels are the Flutter view's physical pixels.
class _LowLatencySource implements SampleSource {
  _LowLatencySource(this._inner, this._style, this._view);

  final SampleSource _inner;
  final WetInkStyle? Function() _style;
  final WetInkView Function() _view;

  PointerDownEvent? _contact;
  WetInkView? _started;
  bool _drawing = false;
  int _processedUs = 0;
  bool _progressScheduled = false;

  @override
  void begin(PointerDownEvent down) {
    _inner.begin(down);
    _contact = down.kind == PointerDeviceKind.stylus ? down : null;
    _drawing = false;
    // The controller has started the live stroke: the overlay draws from
    // the first sample, as Flutter does.
    _start();
  }

  /// Sends `begin` if the contact is ink the overlay can draw.
  void _start() {
    final contact = _contact;
    final style = _style();
    if (contact == null || _drawing || style == null) return;
    final view = _view();
    if (view.clip.isEmpty) return;
    _drawing = true;
    _started = view;
    final dpr = _devicePixelRatio();
    // Local (surface) → Flutter view coordinates → physical pixels.
    final clip = view.clip.shift(contact.position - contact.localPosition);
    _send([
      'begin',
      contact.device,
      contact.timeStamp.inMicroseconds.toDouble(),
      style.color,
      Float64List.fromList([for (final r in style.radii) r * dpr]),
      style.shape.scaled(dpr).toList(),
      Float64List.fromList([clip.left * dpr, clip.top * dpr, clip.right * dpr, clip.bottom * dpr]),
    ]);
  }

  @override
  List<PointerSample> between(PointerEvent event) {
    final samples = _inner.between(event);
    final contact = _contact;
    if (contact == null || event.device != contact.device) return samples;
    final style = _style();
    if (!_drawing && style != null) {
      _start();
    } else if (_drawing && (style == null || !_view().sameTransform(_started!))) {
      // Straightened, no longer ink, or the view moved: Flutter draws it.
      _send(['cancel', contact.device, contact.timeStamp.inMicroseconds.toDouble()]);
      _drawing = false;
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
