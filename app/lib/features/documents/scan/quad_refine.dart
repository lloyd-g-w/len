import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'scan_geometry.dart';

/// Sharpens a coarse document outline (`QuadDetector` works at a few
/// hundred pixels) on a finer luminance image: along each side, the
/// strongest brightness step across it is located to a fraction of a
/// pixel, a line is fitted through those edge points (robustly: text near
/// the edge or a textured table only add outliers) and the corners become
/// the neighbouring lines' intersections.
abstract final class QuadRefiner {
  /// A step across a side weaker than this (grey levels over two pixels)
  /// is no edge.
  static const int minStep = 10;

  /// Edge points further than this from the fitted line (pixels) are
  /// outliers.
  static const double inlierDistance = 1.5;

  /// [quad] (in [grey]'s pixel coordinates, where pixel i covers [i, i + 1))
  /// with its sides moved onto the edges found within [radius] pixels of
  /// them. Sides without a clear edge stay; if the result is implausible
  /// (not convex, a corner moved further than 3 × [radius]) [quad] is
  /// returned as it is.
  static Quad refine(Uint8List grey, int width, int height, Quad quad, {required double radius}) {
    final c = quad.corners;
    final lines = [
      for (var s = 0; s < 4; s++)
        _side(grey, width, height, c[s], c[(s + 1) % 4], radius.ceil()) ??
            (point: c[s], direction: c[(s + 1) % 4] - c[s]),
    ];
    final corners = <Offset>[];
    for (var i = 0; i < 4; i++) {
      final p = _intersect(lines[(i + 3) % 4], lines[i]);
      if (p == null || (p - c[i]).distance > 3 * radius) return quad;
      corners.add(p);
    }
    final refined = Quad.fromCorners(corners);
    return refined.isConvex ? refined : quad;
  }

  /// The edge along side [a] → [b] (corners clockwise on screen, so the
  /// inside is to its right in y-down terms), or null if too few points
  /// on it show a clear step the same way round.
  static _Line? _side(Uint8List g, int w, int h, Offset a, Offset b, int r) {
    final d = b - a;
    final len = d.distance;
    if (len < 8) return null;
    final u = d / len, n = Offset(-u.dy, u.dx); // n points inside.
    final count = (len / 3).round().clamp(12, 120);
    final rising = <Offset>[], falling = <Offset>[]; // (along, across)
    final v = Float64List(2 * r + 3);
    samples:
    for (var i = 0; i < count; i++) {
      final t = 0.1 + 0.8 * i / (count - 1);
      final p = a + d * t;
      for (var k = -r - 1; k <= r + 1; k++) {
        final s = _sample(g, w, h, p + n * k.toDouble());
        if (s < 0) continue samples;
        v[k + r + 1] = s;
      }
      // Central differences at offsets -r..r; the strongest each way.
      var up = 0, down = 0;
      var upStep = 0.0, downStep = 0.0;
      for (var k = -r; k <= r; k++) {
        final step = _grad(v, k + r + 1);
        if (step > upStep) (upStep, up) = (step, k);
        if (-step > downStep) (downStep, down) = (-step, k);
      }
      final along = len * t;
      if (upStep >= minStep) rising.add(Offset(along, up + _peak(v, up + r + 1, 1)));
      if (downStep >= minStep) falling.add(Offset(along, down + _peak(v, down + r + 1, -1)));
    }
    final points = rising.length >= falling.length ? rising : falling;
    final fit = _robustLine(points, len, minInliers: math.max(6, (0.3 * count).ceil()));
    if (fit == null) return null;
    // across = offset + slope · along.
    return (point: a + n * fit.offset, direction: u + n * fit.slope);
  }

  /// Grey at [p] (bilinear between pixel centres), or -1 outside.
  static double _sample(Uint8List g, int w, int h, Offset p) {
    final x = p.dx - 0.5, y = p.dy - 0.5;
    if (!(x >= 0 && y >= 0 && x <= w - 1 && y <= h - 1)) return -1;
    final ix = math.min(x.floor(), w - 2), iy = math.min(y.floor(), h - 2);
    final fx = x - ix, fy = y - iy;
    final o = iy * w + ix;
    final top = g[o] + (g[o + 1] - g[o]) * fx;
    final bottom = g[o + w] + (g[o + w + 1] - g[o + w]) * fx;
    return top + (bottom - top) * fy;
  }

  static double _grad(Float64List v, int i) => v[i + 1] - v[i - 1];

  /// The sub-pixel offset (−½..½) of the extreme of the step at profile
  /// index [i] (a parabola through it and its neighbours), [sign] 1 for a
  /// maximum of the rising step, −1 for the falling one.
  static double _peak(Float64List v, int i, int sign) {
    if (i < 2 || i > v.length - 3) return 0;
    final l = sign * _grad(v, i - 1), m = sign * _grad(v, i), r = sign * _grad(v, i + 1);
    final den = l - 2 * m + r;
    if (den >= 0) return 0;
    return (0.5 * (l - r) / den).clamp(-0.5, 0.5);
  }

  /// A line `across = offset + slope · along` through [points]: Theil–Sen
  /// (median slope of pairs, median offset) to find it among outliers,
  /// then least squares over the points within [inlierDistance]; null if
  /// fewer than [minInliers] are.
  static ({double offset, double slope})? _robustLine(
    List<Offset> points,
    double length, {
    required int minInliers,
  }) {
    if (points.length < minInliers) return null;
    final slopes = <double>[];
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        final dx = points[j].dx - points[i].dx;
        if (dx.abs() > 0.1 * length) slopes.add((points[j].dy - points[i].dy) / dx);
      }
    }
    if (slopes.isEmpty) return null;
    var slope = _median(slopes);
    var offset = _median([for (final p in points) p.dy - slope * p.dx]);
    for (var pass = 0; pass < 2; pass++) {
      final inliers = [
        for (final p in points)
          if ((p.dy - offset - slope * p.dx).abs() <= inlierDistance) p,
      ];
      if (inliers.length < minInliers) return null;
      final mx = inliers.fold(0.0, (s, p) => s + p.dx) / inliers.length;
      final my = inliers.fold(0.0, (s, p) => s + p.dy) / inliers.length;
      var sxy = 0.0, sxx = 0.0;
      for (final p in inliers) {
        sxy += (p.dx - mx) * (p.dy - my);
        sxx += (p.dx - mx) * (p.dx - mx);
      }
      if (sxx <= 0) return null;
      slope = sxy / sxx;
      offset = my - slope * mx;
    }
    return (offset: offset, slope: slope);
  }

  static double _median(List<double> values) {
    values.sort();
    final m = values.length ~/ 2;
    return values.length.isOdd ? values[m] : (values[m - 1] + values[m]) / 2;
  }

  static Offset? _intersect(_Line p, _Line q) {
    final d1 = p.direction, d2 = q.direction;
    final cross = d1.dx * d2.dy - d1.dy * d2.dx;
    if (cross.abs() < 1e-9) return null;
    final e = q.point - p.point;
    final s = (e.dx * d2.dy - e.dy * d2.dx) / cross;
    return p.point + d1 * s;
  }
}

typedef _Line = ({Offset point, Offset direction});
