import 'dart:math' as math;
import 'dart:ui';

import 'package:len/ink/lab/input_recording.dart';
import 'package:len/ink/lab/raw_samples.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/render/stroke_outline.dart';
import 'package:len/ink/render/stroke_renderer.dart';

import 'polyline_index.dart';

/// How far the stabilised ink trails the pen, frame by frame, and what the
/// lift adds: what "the stabiliser is bad when I go fast" is about.
class StabiliserLag {
  StabiliserLag._(this.px, this.ms, this.speed, this.liftTail, this.liftGap);

  /// Per drawing frame (pen moving): distance from the end of the drawn
  /// ink to the newest sample the frame had (px), how long ago the pen was
  /// where the ink ends (ms), and the pen's speed then (px/s).
  final List<double> px, ms, speed;

  /// Per stroke: arc length the lift added beyond the last live frame's
  /// ink (px), and how far that frame's ink ended from where the pen
  /// lifted (px).
  final List<double> liftTail, liftGap;

  /// The [q] quantile of [values] (0 when empty).
  static double quantile(List<double> values, double q) {
    if (values.isEmpty) return 0;
    final s = List.of(values)..sort();
    return s[(q * (s.length - 1)).round()];
  }

  /// The [q] quantile of [px] over frames where the pen moved faster than
  /// [minSpeed] (and slower than [maxSpeed]).
  double pxAt(double q, {double minSpeed = 0, double maxSpeed = double.infinity}) =>
      quantile(_where(px, minSpeed, maxSpeed), q);

  double msAt(double q, {double minSpeed = 0, double maxSpeed = double.infinity}) =>
      quantile(_where(ms, minSpeed, maxSpeed), q);

  List<double> _where(List<double> v, double lo, double hi) => [
    for (var i = 0; i < v.length; i++)
      if (speed[i] >= lo && speed[i] < hi) v[i],
  ];

  /// Measures [replay] of [recording].
  static StabiliserLag of(ReplayResult replay, InputRecording recording) {
    final contacts = rawContacts(recording).where((c) => c.samples.length > 1).toList();
    // The contact a frame draws: the newest that had touched down by then.
    int contactAt(int us) {
      var k = -1;
      for (var i = 0; i < contacts.length; i++) {
        if (contacts[i].downUs <= us) k = i;
      }
      return k;
    }

    final px = <double>[], ms = <double>[], speed = <double>[];
    final liftTail = <double>[], liftGap = <double>[];
    var contact = -1;
    var wasDrawing = false;
    ReplayFrame? last;
    double lastDrawn = 0;
    Offset? lastTip;
    void lifted() {
      final f = last;
      if (f == null || contact < 0 || contact >= contacts.length) return;
      final c = contacts[contact];
      // The committed stroke: the next one committed after the last frame.
      final committed = replay.frames
          .skip(f.index + 1)
          .expand((g) => g.committed.map((s) => (g, s)))
          .firstOrNull;
      if (committed == null) return;
      final (g, s) = committed;
      final spec = StrokeRenderer.specFor(replay.pen.width, s.style);
      final line = StrokeOutline.centerline(s.points, spec);
      if (line == null) return;
      final all = [for (var i = 0; i < line.length; i++) g.toScreen(line.x[i], line.y[i])];
      liftTail.add(math.max(0, _length(all) - lastDrawn));
      if (lastTip case final tip?) liftGap.add((tip - c.samples.last.position).distance);
    }

    for (final f in replay.frames) {
      if (!f.drawing) {
        if (wasDrawing) lifted();
        wasDrawing = false;
        continue;
      }
      final k = contactAt(f.newestEventUs);
      if (wasDrawing && k != contact) lifted();
      contact = k;
      wasDrawing = true;
      last = f;
      if (contact < 0) continue;
      final samples = contacts[contact].samples;
      final spec = StrokeRenderer.specFor(replay.pen.width, f.style);
      final line = StrokeOutline.centerline(f.points, spec, complete: false);
      if (line == null) continue;
      final drawn = [for (var i = 0; i < line.live; i++) f.toScreen(line.x[i], line.y[i])];
      if (f.tip.isNotEmpty) drawn.addAll([for (final p in f.tip) f.toScreen(p.dx, p.dy)]);
      if (drawn.isEmpty) continue;
      lastDrawn = _length(drawn);
      final tip = drawn.last;
      lastTip = tip;
      var pen = -1;
      for (var i = 0; i < samples.length; i++) {
        if (samples[i].timeUs <= f.newestEventUs) pen = i;
      }
      if (pen < 2) continue;
      final p = samples[pen];
      // The pen's speed over the last 8 ms.
      var j = pen;
      while (j > 0 && p.timeUs - samples[j].timeUs < 8000) {
        j--;
      }
      final dt = (p.timeUs - samples[j].timeUs) / 1e6;
      final v = dt > 0 ? (p.position - samples[j].position).distance / dt : 0.0;
      if (v < 20) continue; // Resting: no trail to speak of.
      // Where the pen was when it was where the ink ends: the nearest of the
      // last 400 ms of samples.
      var best = double.infinity, at = pen;
      for (var i = pen; i >= 0 && p.timeUs - samples[i].timeUs < 400000; i--) {
        final d = (samples[i].position - tip).distance;
        if (d < best) {
          best = d;
          at = i;
        }
      }
      px.add((p.position - tip).distance);
      ms.add((p.timeUs - samples[at].timeUs) / 1000);
      speed.add(v);
    }
    if (wasDrawing) lifted();
    return StabiliserLag._(px, ms, speed, liftTail, liftGap);
  }

  static double _length(List<Offset> l) {
    var s = 0.0;
    for (var i = 1; i < l.length; i++) {
      s += (l[i] - l[i - 1]).distance;
    }
    return s;
  }
}

/// How far the committed centre lines of [replay] stray from [truths] (one
/// per stroke, screen px): the largest distance both ways and the RMS from
/// line to truth, and how far each of [cusps] lies from its line.
({double hausdorff, double rms, double cusp}) shapeError(
  ReplayResult replay,
  List<List<Offset>> truths, {
  List<List<Offset>> cusps = const [],
}) {
  var worst = 0.0, sum = 0.0, n = 0, cusp = 0.0;
  final strokes = replay.strokes;
  for (var k = 0; k < math.min(strokes.length, truths.length); k++) {
    final s = strokes[k];
    final toScreen = replay.screenOf(s);
    final spec = StrokeRenderer.specFor(replay.pen.width, s.style);
    final line = StrokeOutline.centerline(s.points, spec);
    if (line == null) continue;
    final pts = [for (var i = 0; i < line.length; i++) toScreen(line.x[i], line.y[i])];
    final truth = PolylineIndex(truths[k], cell: 3);
    final ink = PolylineIndex(pts, cell: 3);
    for (final p in pts) {
      final d = truth.distance(p);
      worst = math.max(worst, d);
      sum += d * d;
      n++;
    }
    for (final p in truths[k]) {
      worst = math.max(worst, ink.distance(p));
    }
    if (k < cusps.length) {
      for (final c in cusps[k]) {
        cusp = math.max(cusp, ink.distance(c));
      }
    }
  }
  return (hausdorff: worst, rms: n == 0 ? 0 : math.sqrt(sum / n), cusp: cusp);
}
