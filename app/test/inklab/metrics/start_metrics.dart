import 'dart:math' as math;
import 'dart:ui';

import 'package:len/ink/lab/raw_samples.dart';
import 'package:len/ink/lab/replay_run.dart';

import 'metric.dart';
import 'outline_geometry.dart';

/// (i) Start latency: ink must appear at pen-down, under the nib.
///
/// For every intended contact ([contacts]: not a bounce), F0 is the first
/// frame built after the pen-down event was handled and Fv the first frame
/// that shows any of the contact's ink (live, or the committed stroke).
///  * `start.delay`: Fv − F0, in frames;
///  * `start.distance`: how far (logical px) the pen was from ink when ink
///    first showed: the raw samples' travel during the frames without ink,
///    or, if there were none, the distance from where the pen landed to
///    the ink of frame Fv (0 when the ink covers it).
List<Metric> start(ReplayResult r, List<RawContact> contacts) {
  final distance = Worst(), delay = Worst();
  final distances = <double>[], delays = <double>[];
  final frames = r.frames;
  var f0 = 0;
  for (final c in contacts) {
    if (c.samples.isEmpty) continue;
    while (f0 < frames.length && frames[f0].newestEventUs < c.downUs) {
      f0++;
    }
    if (f0 >= frames.length) break;
    final landed = c.samples.first.position;
    bool near(double x, double y, Offset Function(double, double) toScreen) =>
        (toScreen(x, y) - landed).distance < 1;
    int? fv;
    for (var k = f0; k < frames.length && fv == null; k++) {
      final f = frames[k];
      if (f.drawing && near(f.points.first.x, f.points.first.y, f.toScreen) ||
          f.committed.any((s) => near(s.points.first.x, s.points.first.y, f.toScreen))) {
        fv = k;
      } else if (f.newestEventUs > c.upUs) {
        break;
      }
    }
    if (fv == null) continue; // No ink at all (judged by ends.stray / fidelity).
    delay.add((fv - f0).toDouble(), landed);
    delays.add((fv - f0).toDouble());
    var d = 0.0;
    if (fv > f0) {
      final seen = frames[fv - 1].newestEventUs;
      for (var i = 1; i < c.samples.length && c.samples[i].timeUs <= seen; i++) {
        d += (c.samples[i].position - c.samples[i - 1].position).distance;
      }
    }
    final f = frames[fv];
    final live = f.drawing && near(f.points.first.x, f.points.first.y, f.toScreen);
    final points = live
        ? f.points
        : f.committed
              .firstWhere((s) => near(s.points.first.x, s.points.first.y, f.toScreen))
              .points;
    final ink = outlineOf(
      points,
      tool: r.pen.tool,
      width: r.pen.width,
      style: r.style,
      complete: !live,
      map: (o) => f.toScreen(o.dx, o.dy),
    ).contours;
    final gap = math.max(d, distanceToInk(landed, ink));
    distance.add(gap, landed);
    distances.add(gap);
  }
  return [
    Metric(
      'start.distance',
      distance.value,
      limit: 0.5,
      unit: 'px',
      where: distance.where,
      note:
          'pen travel from pen-down before ink shows under the nib (median ${_median(distances)})',
    ),
    Metric(
      'start.delay',
      delay.value,
      limit: 1,
      unit: ' frames',
      where: delay.where,
      note: 'frames from pen-down to the first frame with ink (median ${_median(delays)})',
    ),
  ];
}

/// Distance from [p] to the union of [contours] (non-zero winding): 0
/// inside.
double distanceToInk(Offset p, List<Contour> contours) {
  if (contours.isEmpty) return double.infinity;
  var winding = 0;
  var best = double.infinity;
  for (final c in contours) {
    for (var i = 0; i < c.length; i++) {
      final a = c[i], b = c[(i + 1) % c.length];
      if (a.dy <= p.dy) {
        if (b.dy > p.dy && _cross(a, b, p) > 0) winding++;
      } else if (b.dy <= p.dy && _cross(a, b, p) < 0) {
        winding--;
      }
      best = math.min(best, _segDist(p, a, b));
    }
  }
  return winding != 0 ? 0 : best;
}

double _cross(Offset a, Offset b, Offset p) =>
    (b.dx - a.dx) * (p.dy - a.dy) - (p.dx - a.dx) * (b.dy - a.dy);

double _segDist(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (l2 == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

String _median(List<double> v) {
  if (v.isEmpty) return '–';
  final s = List.of(v)..sort();
  return s[s.length ~/ 2].toStringAsFixed(2);
}
