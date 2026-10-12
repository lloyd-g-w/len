import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../ink/input/sample_source.dart';
import '../ink/input/wet_ink.dart';

/// Control messages for the native low-latency ink overlay (`WetInkOverlay.kt`).
const String lowLatencyInkChannel = 'len/low_latency_ink';

const _overlay = BasicMessageChannel<Object?>(lowLatencyInkChannel, StandardMessageCodec());

/// The newest stylus down a [LowLatencySource] answered (`begin` or
/// `skip`), so [_onPointer] can tell the overlay about those none did.
(int, int)? _answered;
bool _routed = false;

/// Every pointer event, after the widgets under it handled it: a stylus
/// down no drawing surface took (a menu over the canvas, a toolbar) is not
/// ink, which the overlay may have started drawing from the armed style.
void _onPointer(PointerEvent event) {
  if (event is! PointerDownEvent || event.kind != PointerDeviceKind.stylus) return;
  final key = (event.device, event.timeStamp.inMicroseconds);
  if (_answered != key) _send(['skip', key.$1, key.$2.toDouble()]);
}

void _send(List<Object?> message) => _overlay.send(message).ignore();

/// Tells the overlay which contact to draw and how far Flutter has got.
///
/// Messages: `[arm, argb, radii px, shape, clip]` or `[arm]` (while the
/// stylus hovers: how a stroke starting now would look, so the overlay can
/// draw from the first sample without waiting for `begin`), `[begin,
/// device, downTimeUs, argb, radii px, shape (`WetInkShape.toList`, px),
/// clip [l, t, r, b] px]` (at pen-down: ink shows from there), `[skip,
/// device, downTimeUs]` (that stylus down is not ink), `[progress,
/// eventTimeUs]` (after a frame showing input up to that event was built),
/// `[end, device, downTimeUs]` (after the frame that shows the finished
/// stroke), `[cancel, device, downTimeUs]` (the overlay's ink is no longer
/// right: remove it now). Pixels are the Flutter view's physical pixels.
class LowLatencySource implements SampleSource {
  /// Draws with [_style] (the stroke's look, null: not overlay ink),
  /// [_next] (the next stroke's, while hovering) and [_view] (where), at
  /// device pixel ratio [_dpr].
  LowLatencySource(this._inner, this._style, this._next, this._view, this._dpr) {
    if (!_routed) {
      _routed = true;
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    }
  }

  final SampleSource _inner;
  final WetInkStyle? Function() _style;
  final WetInkStyle? Function() _next;
  final WetInkView Function() _view;
  final double Function() _dpr;

  PointerDownEvent? _contact;
  WetInkView? _started;
  bool _drawing = false;
  int _processedUs = 0;
  bool _progressScheduled = false;

  // The last `arm` sent and when (µs of the hover event).
  List<Object?>? _armed;
  int _armedAtUs = -_rearmUs;

  /// While hovering, `arm` is re-sent this often (the overlay only trusts a
  /// recent one).
  static const int _rearmUs = 150000;

  @override
  void hover(PointerHoverEvent event) {
    _inner.hover(event);
    if (event.kind != PointerDeviceKind.stylus) return;
    final style = _next();
    final view = _view();
    final message = style == null || view.clip.isEmpty
        ? const ['arm']
        : ['arm', ..._payload(style, view, event.position - event.localPosition)];
    final us = event.timeStamp.inMicroseconds;
    final same = _armed != null && _sameMessage(_armed!, message);
    if (same && us - _armedAtUs < _rearmUs) return;
    _armed = message;
    _armedAtUs = us;
    _send(message);
  }

  @override
  void begin(PointerDownEvent down) {
    _inner.begin(down);
    _contact = down.kind == PointerDeviceKind.stylus ? down : null;
    _drawing = false;
    // The controller has started the live stroke: the overlay draws from
    // the first sample, as Flutter does.
    _start();
    if (_contact != null) {
      _answered = (down.device, down.timeStamp.inMicroseconds);
      if (!_drawing) _send(['skip', down.device, down.timeStamp.inMicroseconds.toDouble()]);
    }
  }

  /// Colour, radii, shape and clip of [style] in [view], in the overlay's
  /// pixels; [origin] is the surface's offset in the Flutter view.
  List<Object?> _payload(WetInkStyle style, WetInkView view, Offset origin) {
    final dpr = _dpr();
    final clip = view.clip.shift(origin);
    return [
      style.color,
      Float64List.fromList([for (final r in style.radii) r * dpr]),
      style.shape.scaled(dpr).toList(),
      Float64List.fromList([clip.left * dpr, clip.top * dpr, clip.right * dpr, clip.bottom * dpr]),
    ];
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
    _send([
      'begin',
      contact.device,
      contact.timeStamp.inMicroseconds.toDouble(),
      ..._payload(style, view, contact.position - contact.localPosition),
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
  void end({double taperEnd = 0}) {
    _inner.end();
    _finish(taperEnd);
    _contact = null;
  }

  /// `end`, with the committed stroke's end taper in the overlay's pixels.
  void _finish(double taperEnd) {
    final contact = _contact;
    if (!_drawing || contact == null) return;
    _drawing = false;
    final message = [
      'end',
      contact.device,
      contact.timeStamp.inMicroseconds.toDouble(),
      taperEnd * _started!.scale * _dpr(),
    ];
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

  static bool _sameMessage(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x is Float64List && y is Float64List) {
        if (x.length != y.length) return false;
        for (var j = 0; j < x.length; j++) {
          if (x[j] != y[j]) return false;
        }
      } else if (x != y) {
        return false;
      }
    }
    return true;
  }
}
