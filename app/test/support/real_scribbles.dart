import 'dart:math' as math;
import 'dart:ui';

import 'package:len/ink/input/scribble_detector.dart';
import 'package:len/ink/lab/raw_samples.dart';

/// Whether [samples] hold a scribble, fed to a [ScribbleDetector] as the
/// pen draws them.
bool scribbles(List<RawSample> samples) {
  final d = ScribbleDetector()..begin(samples.first.position, samples.first.timeUs ~/ 1000);
  for (final s in samples.skip(1)) {
    d.add(s.position, s.timeUs ~/ 1000);
  }
  return (d..finish()).isScribble;
}

/// [samples] scaled by [scale] about their start and drawn at [pace]
/// times their duration (0.5: twice as fast).
List<RawSample> rescaled(List<RawSample> samples, {double scale = 1, double pace = 1}) {
  final o = samples.first.position, t0 = samples.first.timeUs;
  return [
    for (final s in samples)
      RawSample(o + (s.position - o) * scale, s.pressure, ((s.timeUs - t0) * pace).round()),
  ];
}

/// A real zigzag ([samples]: passes back and forth, moving on across
/// them) made a scribble: its passes [amplitude] long, squeezed across
/// them into a band [spread] × the amplitude wide, each taking [passMs]
/// on average. The pen's own turns, speed changes within and between
/// passes, pressure and jitter stay.
List<RawSample> squeezed(
  List<RawSample> samples, {
  required double amplitude,
  required double spread,
  required double passMs,
}) {
  // The passes' direction: the principal axis of the pen's steps.
  var sxx = 0.0, syy = 0.0, sxy = 0.0;
  for (var i = 1; i < samples.length; i++) {
    final d = samples[i].position - samples[i - 1].position;
    sxx += d.dx * d.dx;
    syy += d.dy * d.dy;
    sxy += d.dx * d.dy;
  }
  final angle = 0.5 * math.atan2(2 * sxy, sxx - syy);
  final u = Offset(math.cos(angle), math.sin(angle)), n = Offset(-u.dy, u.dx);
  final along = [for (final s in samples) s.position.dx * u.dx + s.position.dy * u.dy];
  final across = [for (final s in samples) s.position.dx * n.dx + s.position.dy * n.dy];
  final a0 = along.reduce(math.min), a1 = along.reduce(math.max);
  final b0 = across.reduce(math.min), b1 = across.reduce(math.max);
  final passes = _passes(along, 0.2 * (a1 - a0));
  final t0 = samples.first.timeUs, duration = samples.last.timeUs - t0;
  final ka = amplitude / (a1 - a0), kb = spread * amplitude / math.max(1e-9, b1 - b0);
  final kt = passMs * 1000 * passes / duration;
  return [
    for (var i = 0; i < samples.length; i++)
      RawSample(
        const Offset(500, 500) + Offset((along[i] - a0) * ka, (across[i] - b0) * kb),
        samples[i].pressure,
        ((samples[i].timeUs - t0) * kt).round(),
      ),
  ];
}

/// How many passes [along] makes: turns back by more than [turn].
int _passes(List<double> along, double turn) {
  var passes = 1, direction = 0;
  var extreme = along.first;
  for (final v in along) {
    if (direction >= 0 && v > extreme) {
      extreme = v;
      direction = 1;
    } else if (direction <= 0 && v < extreme) {
      extreme = v;
      direction = -1;
    } else if ((v - extreme).abs() > turn) {
      passes++;
      direction = -direction;
      extreme = v;
    }
  }
  return passes;
}
