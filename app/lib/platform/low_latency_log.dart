import 'dart:developer' show Timeline;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';

import '../domain/stroke.dart';
import '../ink/input/sample_source.dart';
import '../ink/input/wet_ink.dart';
import '../ink/lab/flicker_geometry.dart';
import '../ink/lab/flicker_log.dart';
import '../ink/lab/wet_ink_model.dart';
import '../ink/render/stroke_renderer.dart';

/// The Dart side of the flicker log for the Android low-latency overlay
/// ([FlickerLog], docs/INK_LAB.md *Flicker log*): turns the overlay's
/// messages (`released`, `retract`, `pruned`) and Flutter's frame timings
/// into log entries, and while it records, keeps each contact's samples as
/// the overlay saw them to measure its geometry against the committed
/// stroke. Costs nothing while [FlickerLog.enabled] is off.
class LowLatencyLog {
  LowLatencyLog(this._send, {FlickerLog? log}) : log = log ?? FlickerLog.instance {
    this.log.addListener(_sync);
    _sync();
  }

  final void Function(List<Object?> message) _send;
  final FlickerLog log;
  bool? _sent;

  // The contacts recorded lately, by (device, down time µs).
  final Map<(int, int), LoggedContact> _contacts = {};

  bool get recording => log.enabled;

  static int get _now => Timeline.now;

  void _sync() {
    final on = log.enabled;
    if (on == _sent) return;
    _sent = on;
    _send(['log', on]);
    final binding = SchedulerBinding.instance;
    if (on) {
      final hz = PlatformDispatcher.instance.displays.firstOrNull?.refreshRate ?? 0;
      if (hz >= 30) log.frameUs = (1e6 / hz).round();
      binding.addTimingsCallback(log.frameTimings);
    } else {
      binding.removeTimingsCallback(log.frameTimings);
    }
  }

  /// A message from the overlay.
  void handle(List<Object?> m) {
    switch (m) {
      case ['released', final int id, final int atMs]:
        log.frameReleased(id, atMs * 1000);
      case ['retract', final double px, final int atMs]:
        log.retract(px, atMs * 1000);
      case ['pruned', final int device, final double downUs, final int atMs, final String how, ...]:
        final at = atMs * 1000;
        final samples = m.length > 5 ? m[5]! as int : 0;
        final frameId = m.length > 6 ? m[6]! as int : -1;
        if (how == 'shown') {
          if (frameId >= 0) log.frameReleased(frameId, at, end: true);
          final seen = _contacts[(device, downUs.round())]?.samples.length;
          if (seen != null) log.samples(seen, samples, at);
        } else {
          log.note(
            how,
            'the overlay dropped a stroke Dart never ${how == 'lost' ? 'ended' : 'answered'}',
            at,
          );
        }
    }
  }

  /// Dart reported frame [id] to the overlay.
  void reported(int id) {
    if (recording) log.frameReported(id, _now);
  }

  /// Frame [id] showed a committed stroke.
  void ended(int id) {
    if (recording) log.frameEnded(id);
  }

  /// The overlay stopped drawing a stroke ([why]).
  void cancelled(String why) => log.note('cancel', why, _now);

  /// Starts recording the samples of [down]'s contact, drawn with
  /// [style] in [view] at [dpr] (null when not recording).
  LoggedContact? begin(PointerDownEvent down, WetInkStyle style, WetInkView view, double dpr) {
    if (!recording) return null;
    final c = LoggedContact(style, view, dpr, down.position - down.localPosition)
      ..add(down, const []);
    _contacts[(down.device, down.timeStamp.inMicroseconds)] = c;
    while (_contacts.length > 8) {
      _contacts.remove(_contacts.keys.first);
    }
    return c;
  }

  /// Measures how far the overlay's ink of [contact] reached outside the
  /// [committed] stroke Flutter shows (after the frame showing it).
  void measure(LoggedContact contact, Stroke committed) {
    if (!recording || contact.samples.isEmpty) return;
    final s = contact.style, dpr = contact.dpr, view = contact.view;
    final model = WetInkModel(
      radii: [for (final r in s.radii) r * dpr],
      shape: s.shape.scaled(dpr),
      frameMs: log.frameUs / 1000,
    );
    for (final (i, p) in contact.samples.indexed) {
      model.add(p.position, p.pressure, p.timeMs, lift: i == contact.samples.length - 1);
    }
    final spec = StrokeRenderer.specFor(committed.width, committed.style);
    model.commit(taperEnd: spec.taperEnd * view.scale * dpr);
    final path = StrokeRenderer.pathOf(committed);
    bool inside(Offset px) => path.contains((px / dpr - contact.origin - view.offset) / view.scale);
    final (excess, at) = overlayExcess(model.segments(0, model.samples.length), inside);
    log.geometry(excess, at ?? Offset.zero, _now);
  }
}

/// The samples of one contact as the overlay got them (Flutter view px,
/// pressure normalised by the device's range, event time in ms).
class LoggedContact {
  LoggedContact(this.style, this.view, this.dpr, this.origin);

  final WetInkStyle style;
  final WetInkView view;
  final double dpr;

  /// The surface's offset in the Flutter view (logical px).
  final Offset origin;
  final List<WetSample> samples = [];

  /// Adds the merged [extra] samples before [event], then [event]'s own.
  void add(PointerEvent event, List<PointerSample> extra) {
    final shift = event.position - event.localPosition;
    final span = event.pressureMax - event.pressureMin;
    double pressure(double raw) => span > 0 ? (raw - event.pressureMin) / span : 0.5;
    for (final s in extra) {
      samples.add(
        WetSample(
          (s.localPosition + shift) * dpr,
          pressure(s.pressure),
          s.timeStamp.inMicroseconds ~/ 1000,
        ),
      );
    }
    samples.add(
      WetSample(
        event.position * dpr,
        pressure(event.pressure),
        event.timeStamp.inMicroseconds ~/ 1000,
      ),
    );
  }
}
