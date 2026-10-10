import 'dart:math' as math;
import 'dart:ui';

import '../../domain/stroke.dart';

/// Shape parameters for [StrokeOutline.build].
class OutlineSpec {
  const OutlineSpec({
    required this.width,
    required this.thinning,
    required this.streamline,
    this.easing = _linear,
    this.taperStart = 0,
    this.taperEnd = 0,
    this.flatCaps = false,
  });

  /// Nominal diameter at medium (0.5) pressure, in world units.
  final double width;

  /// How strongly pressure changes the width, 0..1.
  final double thinning;

  /// Stabiliser strength, 0..1: how much positional jitter is smoothed away.
  final double streamline;

  /// Maps the pressure-derived size factor (0..1) to a radius factor.
  final double Function(double) easing;

  /// Lengths (world units) over which the ends taper to a point; 0 = none.
  final double taperStart;
  final double taperEnd;

  /// Square ends (highlighter) instead of round caps.
  final bool flatCaps;

  static double _linear(double t) => t;

  /// Outline radius at [pressure]: half the [width] at medium pressure,
  /// thinner/thicker with lighter/harder pressure as [thinning] allows.
  double radiusFor(double pressure) {
    final t = (0.5 - thinning * (0.5 - pressure)).clamp(0.0, 1.0);
    return (width * easing(t)).clamp(math.min(0.25, width / 2), width);
  }
}

/// A sample along the stroke centre line: position and outline radius.
class _Sample {
  _Sample(this.x, this.y, this.r);
  final double x, y;
  double r;

  Offset get offset => Offset(x, y);
}

/// Builds filled outline paths for variable-width ink strokes.
///
/// Pipeline: drop duplicate samples → trim pen-lift hooks → smooth positions
/// with a symmetric (lag-free) filter → map pressure to radius and smooth it
/// → interpolate a Catmull-Rom spline → apply tapers → emit one outline per
/// run between sharp corners, each closed with caps that exactly match the
/// local width and direction. Runs overlap at corners, which yields round
/// joins; all runs wind the same way, so the non-zero fill unions them.
abstract final class StrokeOutline {
  /// Builds the outline of [points]. [pressures], when given, overrides the
  /// per-point pressure (used for direction-dependent nibs). [complete] is
  /// false while the stroke is still being drawn: its moving end is then
  /// left untrimmed.
  static Path build(
    List<StrokePoint> points,
    OutlineSpec spec, {
    List<double>? pressures,
    bool complete = true,
  }) {
    var samples = _dedupe(points, pressures, spec);
    if (samples.isEmpty) return Path();
    if (samples.length > 3) {
      samples = _trimHook(samples, spec.width, atEnd: false);
      if (complete) samples = _trimHook(samples, spec.width, atEnd: true);
    }
    samples = _smoothPositions(samples, (spec.streamline * 6).round().clamp(0, 5));
    _smoothRadii(samples, 2, spec.width);
    final curve = _interpolate(samples, _step(spec.width));
    final length = _applyTapers(curve, spec);
    final maxR = curve.fold<double>(0, (m, s) => math.max(m, s.r));
    if (curve.length < 2 || length < maxR * 0.5) return _dot(curve.first, maxR, spec.flatCaps);
    final path = Path();
    for (final run in _runs(curve)) {
      _addRun(path, run, spec.flatCaps);
    }
    return path;
  }

  // ---------------------------------------------------------------------------
  // Pipeline stages

  static List<_Sample> _dedupe(
    List<StrokePoint> points,
    List<double>? pressures,
    OutlineSpec spec,
  ) {
    final eps = math.max(0.01, spec.width * 0.02);
    final out = <_Sample>[];
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final r = spec.radiusFor(pressures?[i] ?? p.pressure);
      if (out.isNotEmpty && (Offset(p.x, p.y) - out.last.offset).distance < eps) {
        out.last.r = math.max(out.last.r, r);
        continue;
      }
      out.add(_Sample(p.x, p.y, r));
    }
    return out;
  }

  /// Removes a short end segment that doubles back (the flick a pen makes
  /// as it lands or lifts), which would otherwise render as a nub. The cut
  /// is made at the furthest point (within a short reach of the end) where
  /// the remaining tail turns back by more than 90° against the body.
  static List<_Sample> _trimHook(List<_Sample> s, double width, {required bool atEnd}) {
    final maxHook = math.max(2.0, width * 1.2);
    final seq = atEnd ? s.reversed.toList() : s;
    var cut = 0;
    var length = 0.0;
    for (var j = 1; j + 3 < seq.length; j++) {
      length += (seq[j].offset - seq[j - 1].offset).distance;
      if (length > maxHook) break;
      final hook = seq[0].offset - seq[j].offset;
      final body = seq[j].offset - seq[j + 3].offset;
      if (hook.distance == 0 || body.distance == 0) continue;
      if (hook.dx * body.dx + hook.dy * body.dy < 0) cut = j;
    }
    if (cut == 0) return s;
    final kept = seq.sublist(cut);
    return atEnd ? kept.reversed.toList() : kept;
  }

  /// Symmetric triangular moving average; the window shrinks near the ends
  /// so the endpoints stay exactly where the pen was.
  static List<_Sample> _smoothPositions(List<_Sample> s, int window) {
    if (window == 0 || s.length < 3) return s;
    return List.generate(s.length, (i) {
      final k = math.min(window, math.min(i, s.length - 1 - i));
      var x = 0.0, y = 0.0, total = 0.0;
      for (var j = -k; j <= k; j++) {
        final w = (k + 1 - j.abs()).toDouble();
        x += s[i + j].x * w;
        y += s[i + j].y * w;
        total += w;
      }
      return _Sample(x / total, y / total, s[i].r);
    });
  }

  /// Averages radii over neighbours, then makes both ends of the stroke
  /// non-swelling: within about one width of either end the radius may only
  /// stay level or shrink towards the tip. Pressure spikes at pen-down or
  /// pen-up therefore can never become blob-shaped caps.
  static void _smoothRadii(List<_Sample> s, int window, double width) {
    if (s.length < 3) return;
    final radii = [for (final p in s) p.r];
    for (var i = 0; i < s.length; i++) {
      final k = math.min(window, math.min(i, s.length - 1 - i));
      var sum = 0.0;
      for (var j = -k; j <= k; j++) {
        sum += radii[i + j];
      }
      s[i].r = sum / (2 * k + 1);
    }
    _settleEnd(s, width);
    final reversed = s.reversed.toList();
    _settleEnd(reversed, width);
  }

  /// Walks from the stroke's interior towards its last sample, capping each
  /// radius at the previous one over the final [reach] of length.
  static void _settleEnd(List<_Sample> s, double reach) {
    var length = 0.0;
    var i = s.length - 1;
    while (i > 0 && length < reach) {
      length += (s[i].offset - s[i - 1].offset).distance;
      i--;
    }
    for (var j = i + 1; j < s.length; j++) {
      s[j].r = math.min(s[j].r, s[j - 1].r);
    }
  }

  /// Spacing of interpolated samples: dense enough that straight outline
  /// segments look curved at any zoom, sparse enough to stay cheap.
  static double _step(double width) => (width * 0.3).clamp(0.4, 3.0);

  /// Catmull-Rom interpolation through the samples.
  static List<_Sample> _interpolate(List<_Sample> s, double step) {
    if (s.length < 3) return s;
    final out = <_Sample>[s.first];
    for (var i = 0; i < s.length - 1; i++) {
      final p0 = s[math.max(0, i - 1)], p1 = s[i], p2 = s[i + 1];
      final p3 = s[math.min(s.length - 1, i + 2)];
      final n = ((p2.offset - p1.offset).distance / step).ceil().clamp(1, 24);
      for (var j = 1; j <= n; j++) {
        final t = j / n;
        out.add(
          _Sample(
            _catmullRom(p0.x, p1.x, p2.x, p3.x, t),
            _catmullRom(p0.y, p1.y, p2.y, p3.y, t),
            p1.r + (p2.r - p1.r) * t,
          ),
        );
      }
    }
    return out;
  }

  static double _catmullRom(double a, double b, double c, double d, double t) {
    final t2 = t * t, t3 = t2 * t;
    return 0.5 *
        (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (3 * b - a - 3 * c + d) * t3);
  }

  /// Narrows the radius towards tapered ends; returns the total length.
  static double _applyTapers(List<_Sample> s, OutlineSpec spec) {
    final along = List<double>.filled(s.length, 0);
    for (var i = 1; i < s.length; i++) {
      along[i] = along[i - 1] + (s[i].offset - s[i - 1].offset).distance;
    }
    final length = along.last;
    final start = math.min(spec.taperStart, length / 2);
    final end = math.min(spec.taperEnd, length / 2);
    if (start <= 0 && end <= 0) return length;
    double ease(double t) => t * (2 - t);
    for (var i = 0; i < s.length; i++) {
      var f = 1.0;
      if (start > 0) f = math.min(f, ease((along[i] / start).clamp(0.0, 1.0)));
      if (end > 0) f = math.min(f, ease(((length - along[i]) / end).clamp(0.0, 1.0)));
      s[i].r = math.max(0.02, s[i].r * f);
    }
    return length;
  }

  /// Splits the curve at sharp corners; neighbouring runs share the corner.
  static List<List<_Sample>> _runs(List<_Sample> s) {
    const sharpCos = 0.3; // ≈ 72° turn
    final runs = <List<_Sample>>[];
    var start = 0;
    Offset? prevDir;
    for (var i = 1; i < s.length; i++) {
      final d = s[i].offset - s[i - 1].offset;
      if (d.distance == 0) continue;
      final dir = d / d.distance;
      if (prevDir != null && dir.dx * prevDir.dx + dir.dy * prevDir.dy < sharpCos) {
        runs.add(s.sublist(start, i));
        start = i - 1;
      }
      prevDir = dir;
    }
    runs.add(s.sublist(start));
    return runs.where((r) => r.length >= 2).toList();
  }

  /// Appends one closed outline: left side forward, end cap, right side
  /// back, start cap. Winding is the same for every run.
  static void _addRun(Path path, List<_Sample> run, bool flatCaps) {
    final n = run.length;
    final normals = List<Offset>.generate(n, (i) {
      final d = run[math.min(n - 1, i + 1)].offset - run[math.max(0, i - 1)].offset;
      final len = d.distance;
      return len == 0 ? const Offset(0, 1) : Offset(-d.dy / len, d.dx / len);
    });
    Offset left(int i) => run[i].offset + normals[i] * run[i].r;
    Offset right(int i) => run[i].offset - normals[i] * run[i].r;

    path.moveTo(left(0).dx, left(0).dy);
    for (var i = 1; i < n; i++) {
      path.lineTo(left(i).dx, left(i).dy);
    }
    _cap(path, run[n - 1], normals[n - 1], right(n - 1), flatCaps);
    for (var i = n - 2; i >= 0; i--) {
      path.lineTo(right(i).dx, right(i).dy);
    }
    _cap(path, run[0], -normals[0], left(0), flatCaps);
    path.close();
  }

  /// Joins the current point (on the side [normal] points to) to [to] around
  /// [at], bulging forwards (away from the stroke body).
  static void _cap(Path path, _Sample at, Offset normal, Offset to, bool flat) {
    if (flat) {
      path.lineTo(to.dx, to.dy);
      return;
    }
    path.arcTo(
      Rect.fromCircle(center: at.offset, radius: at.r),
      math.atan2(normal.dy, normal.dx),
      -math.pi,
      false,
    );
  }

  static Path _dot(_Sample at, double r, bool flat) {
    final rect = Rect.fromCircle(center: at.offset, radius: math.max(r, 0.25));
    return flat ? (Path()..addRect(rect)) : (Path()..addOval(rect));
  }
}
