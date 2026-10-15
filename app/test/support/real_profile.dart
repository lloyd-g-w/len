import 'dart:math' as math;
import 'dart:ui';

import 'package:len/ink/lab/raw_samples.dart';

/// How a real stroke was drawn, apart from its path: when each sample
/// came, how far along the path the pen was then, the pressure, and the
/// jitter around the smoothed path, across and along it.
class RealProfile {
  RealProfile._(this.timesUs, this.progress, this.pressures, this.jitter, this.length);

  /// The profile of [contact], its jitter what a fit over [smoothingMs]
  /// either side does not follow: 8 ms leaves the digitiser's noise,
  /// 25 ms the hand's tremor too.
  factory RealProfile.of(RawContact contact, {double smoothingMs = 8}) {
    final s = contact.samples;
    final t0 = s.first.timeUs;
    final times = [for (final x in s) x.timeUs - t0];
    final smooth = _smoothed(s, smoothingMs);
    final along = <double>[0];
    for (var i = 1; i < smooth.length; i++) {
      along.add(along.last + (smooth[i] - smooth[i - 1]).distance);
    }
    final length = along.last;
    // Away from the ends, where the smoothing is one-sided and lags.
    final edge = 3 * smoothingMs * 1000;
    final jitter = <Offset>[];
    for (var i = 0; i < s.length; i++) {
      if (times[i] < edge || times.last - times[i] < edge) continue;
      final d = s[i].position - smooth[i];
      final u = _tangent(smooth, i);
      jitter.add(Offset(d.dx * u.dx + d.dy * u.dy, -d.dx * u.dy + d.dy * u.dx));
    }
    return RealProfile._(
      times,
      [for (final a in along) length == 0 ? 0 : a / length],
      [for (final x in s) x.pressure],
      jitter.isEmpty ? const [Offset.zero] : jitter,
      length,
    );
  }

  final List<int> timesUs;

  /// Share of the path's length drawn by each sample (0..1).
  final List<double> progress;
  final List<double> pressures;

  /// Each sample's offset from the smoothed path (along, across it),
  /// away from the stroke's ends.
  final List<Offset> jitter;

  /// Length of the smoothed path (px).
  final double length;

  int get durationUs => timesUs.last;

  /// Mean speed (px per ms).
  double get speed => length / math.max(1, durationUs / 1000);

  /// [path] (a dense polyline) drawn as this stroke was: over [durationMs]
  /// (by default at this stroke's mean speed), sampled at its sample
  /// intervals, as far along at each moment (in share of the time) as the
  /// real pen was, with its pressure and its jitter (turned into the
  /// path's direction there).
  List<RawSample> apply(List<Offset> path, {double? durationMs}) {
    final cumulative = <double>[0];
    for (var i = 1; i < path.length; i++) {
      cumulative.add(cumulative.last + (path[i] - path[i - 1]).distance);
    }
    final total = cumulative.last;
    final duration = ((durationMs ?? total / speed) * 1000).round();
    final out = <RawSample>[];
    var t = 0, k = 0;
    while (true) {
      final f = math.min(1.0, t / duration);
      final at = _lookup(f * durationUs);
      final (point, u) = _pointAt(path, cumulative, at.progress * total);
      final j = jitter[k % jitter.length];
      final offset = Offset(u.dx * j.dx - u.dy * j.dy, u.dy * j.dx + u.dx * j.dy);
      out.add(RawSample(point + offset, at.pressure, t));
      if (f >= 1) break;
      final step = timesUs[(k % (timesUs.length - 1)) + 1] - timesUs[k % (timesUs.length - 1)];
      t = math.min(duration, t + math.max(250, step));
      k++;
    }
    return out;
  }

  /// Progress and pressure at [us] into the real stroke (interpolated).
  ({double progress, double pressure}) _lookup(double us) {
    var lo = 0, hi = timesUs.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (timesUs[mid] <= us) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = timesUs[hi] - timesUs[lo];
    final w = span == 0 ? 0.0 : ((us - timesUs[lo]) / span).clamp(0.0, 1.0);
    return (
      progress: progress[lo] + (progress[hi] - progress[lo]) * w,
      pressure: pressures[lo] + (pressures[hi] - pressures[lo]) * w,
    );
  }

  static (Offset, Offset) _pointAt(List<Offset> path, List<double> cumulative, double d) {
    var i = 1;
    while (i < path.length - 1 && cumulative[i] < d) {
      i++;
    }
    final a = path[i - 1], b = path[i];
    final seg = cumulative[i] - cumulative[i - 1];
    final w = seg == 0 ? 0.0 : ((d - cumulative[i - 1]) / seg).clamp(0.0, 1.0);
    final v = b - a;
    final u = v.distance == 0 ? const Offset(1, 0) : v / v.distance;
    return (Offset.lerp(a, b, w)!, u);
  }

  /// Each sample's position on a quadratic in time fitted to the samples
  /// within [smoothingMs] of it (unweighted least squares): the hand's
  /// motion, turns included, without the jitter.
  static List<Offset> _smoothed(List<RawSample> s, double smoothingMs) {
    final reach = smoothingMs * 1000;
    return [
      for (var i = 0; i < s.length; i++)
        () {
          var lo = i, hi = i;
          while (lo > 0 && s[i].timeUs - s[lo - 1].timeUs <= reach) {
            lo--;
          }
          while (hi < s.length - 1 && s[hi + 1].timeUs - s[i].timeUs <= reach) {
            hi++;
          }
          if (hi - lo < 3) return s[i].position;
          return _quadraticAt([
            for (var k = lo; k <= hi; k++) ((s[k].timeUs - s[i].timeUs) / 1000.0, s[k].position),
          ]);
        }(),
    ];
  }

  /// The value at t = 0 of the least-squares quadratic through [points].
  static Offset _quadraticAt(List<(double, Offset)> points) {
    // Normal equations for a + b t + c t², solved by Cramer's rule.
    var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0, s4 = 0.0;
    var x0 = Offset.zero, x1 = Offset.zero, x2 = Offset.zero;
    for (final (t, p) in points) {
      final t2 = t * t;
      s0 += 1;
      s1 += t;
      s2 += t2;
      s3 += t2 * t;
      s4 += t2 * t2;
      x0 += p;
      x1 += p * t;
      x2 += p * t2;
    }
    final det = s0 * (s2 * s4 - s3 * s3) - s1 * (s1 * s4 - s3 * s2) + s2 * (s1 * s3 - s2 * s2);
    if (det.abs() < 1e-12) return x0 / s0;
    double solve(double v0, double v1, double v2) =>
        (v0 * (s2 * s4 - s3 * s3) - s1 * (v1 * s4 - s3 * v2) + s2 * (v1 * s3 - s2 * v2)) / det;
    return Offset(solve(x0.dx, x1.dx, x2.dx), solve(x0.dy, x1.dy, x2.dy));
  }

  static Offset _tangent(List<Offset> p, int i) {
    final d = p[math.min(p.length - 1, i + 1)] - p[math.max(0, i - 1)];
    return d.distance == 0 ? const Offset(1, 0) : d / d.distance;
  }
}
