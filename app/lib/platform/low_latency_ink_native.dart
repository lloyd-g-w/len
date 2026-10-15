import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../domain/stroke.dart';
import '../ink/input/sample_source.dart';
import '../ink/input/wet_ink.dart';
import '../ink/render/stroke_renderer.dart';
import 'low_latency_frames.dart';
import 'low_latency_log.dart';

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

/// The frames built while the overlay draws, reported to it.
final LowLatencyFrames lowLatencyFrames = LowLatencyFrames(_send);

/// The flicker log's side of the overlay's messages (created with the
/// first source: it needs the bindings).
LowLatencyLog? _log;

LowLatencyLog get _flicker => _log ??= () {
  final log = LowLatencyLog(_send);
  lowLatencyFrames.onReport = log.reported;
  _overlay.setMessageHandler((m) async {
    if (m is List<Object?>) log.handle(m);
    return null;
  });
  return log;
}();

/// Tells the overlay which contact to draw and how far Flutter has got.
///
/// Messages: `[arm, argb, radii px, shape, clip]` or `[arm]` (while the
/// stylus hovers: how a stroke starting now would look, so the overlay can
/// draw from the first sample without waiting for `begin`), `[begin,
/// device, downTimeUs, argb, radii px, shape (`WetInkShape.toList`, px),
/// clip [l, t, r, b] px]` (at pen-down: ink shows from there), `[skip,
/// device, downTimeUs]` (that stylus down is not ink), `[progress,
/// eventTimeUs, frameId]` (after each frame built while there is overlay
/// ink: it shows input up to that event; [LowLatencyFrames]), `[end,
/// device, downTimeUs, taperEnd px]` (right after the report of the frame
/// that shows the committed stroke), `[cancel, device, downTimeUs]` (the
/// overlay's ink is no longer right: remove it now). Pixels are the
/// Flutter view's physical pixels.
class LowLatencySource implements SampleSource {
  /// Draws with [_style] (the stroke's look, null: not overlay ink),
  /// [_next] (the next stroke's, while hovering) and [_view] (where), at
  /// device pixel ratio [_dpr].
  LowLatencySource(this._inner, this._style, this._next, this._view, this._dpr) {
    if (!_routed) {
      _routed = true;
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    }
    _flicker;
  }

  final SampleSource _inner;
  final WetInkStyle? Function() _style;
  final WetInkStyle? Function() _next;
  final WetInkView Function() _view;
  final double Function() _dpr;

  PointerDownEvent? _contact;
  WetInkView? _started;
  bool _drawing = false;

  /// The contact's samples, while the flicker log records.
  LoggedContact? _logged;

  // The last `arm` sent and when (µs of the hover event).
  List<Object?>? _armed;
  int _armedAtUs = -_rearmUs;

  /// While hovering, `arm` is re-sent this often (the overlay only trusts a
  /// recent one).
  static const int _rearmUs = 150000;

  /// How long after `end` the overlay may still draw a stroke, at most
  /// (`WetInkHandover.LOST_AFTER_MS`): the view moving meanwhile cancels it.
  static const Duration _heldAfterEnd = Duration(seconds: 1);

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
    _logged = _flicker.begin(contact, style, view, _dpr());
    _send([
      'begin',
      contact.device,
      contact.timeStamp.inMicroseconds.toDouble(),
      ..._payload(style, view, contact.position - contact.localPosition),
    ]);
    lowLatencyFrames.input(contact.timeStamp.inMicroseconds);
  }

  @override
  List<PointerSample> between(PointerEvent event) {
    final samples = _inner.between(event);
    final contact = _contact;
    if (contact == null || event.device != contact.device) return samples;
    final style = _style();
    if (!_drawing && style != null) {
      _start();
      _logged = null; // Started late: its samples so far are not known here.
    } else if (_drawing && style == null) {
      // Straightened, or no longer ink: Flutter draws it (the pen rests
      // when a stroke snaps, so Flutter's frames have caught up).
      _send(_cancel(contact));
      _flicker.cancelled('straightened (or no longer ink) while writing');
      _drawing = false;
      _contact = null;
      return samples;
    } else if (_drawing && !_view().sameTransform(_started!)) {
      // The view moved: Flutter draws the stroke elsewhere from the next
      // frame on; the overlay's ink goes once that frame is built.
      _drawing = false;
      _contact = null;
      lowLatencyFrames.afterNextFrame(() => _send(_cancel(contact)));
      _flicker.cancelled('the view moved while writing');
      return samples;
    }
    if (_drawing) {
      _logged?.add(event, samples);
      lowLatencyFrames.input(event.timeStamp.inMicroseconds);
    }
    return samples;
  }

  @override
  void end({Stroke? committed}) {
    _inner.end();
    final contact = _contact;
    if (_drawing && contact != null) _finish(contact, committed);
    _drawing = false;
    _contact = null;
  }

  /// After the next frame (built without the live stroke): `end`, with
  /// the [committed] stroke's end taper in the overlay's pixels, or
  /// `cancel` when nothing was committed or the view moved. Until the
  /// overlay has let go, a view that moves cancels it (its ink would stay
  /// where the stroke was on the screen).
  void _finish(PointerDownEvent contact, Stroke? committed) {
    final view = _started!;
    final logged = _logged;
    _logged = null;
    if (committed == null) {
      // A bounce, a scribble that erased, a cancelled contact: Flutter's
      // frames show the live stroke until the one without it, so the
      // overlay's tail goes with that frame (not after it, alone).
      lowLatencyFrames.afterNextFrame(() => _send(_cancel(contact)));
      _flicker.cancelled('nothing committed (a bounce, a scribble that erased)');
      return;
    }
    final taper = StrokeRenderer.specFor(committed.width, committed.style).taperEnd;
    lowLatencyFrames.afterNextFrame(() {
      if (!_view().sameTransform(view)) {
        _flicker.cancelled('the view moved at the lift');
        return _send(_cancel(contact));
      }
      _send([
        'end',
        contact.device,
        contact.timeStamp.inMicroseconds.toDouble(),
        taper * view.scale * _dpr(),
      ]);
      _flicker.ended(lowLatencyFrames.frameId);
      if (logged != null) scheduleMicrotask(() => _flicker.measure(logged, committed));
      final until = SchedulerBinding.instance.currentSystemFrameTimeStamp + _heldAfterEnd;
      lowLatencyFrames.watch(() {
        if (SchedulerBinding.instance.currentSystemFrameTimeStamp > until) return false;
        if (_view().sameTransform(view)) return true;
        _send(_cancel(contact));
        _flicker.cancelled('the view moved after the lift');
        return false;
      });
    });
  }

  static List<Object?> _cancel(PointerDownEvent contact) => [
    'cancel',
    contact.device,
    contact.timeStamp.inMicroseconds.toDouble(),
  ];

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
