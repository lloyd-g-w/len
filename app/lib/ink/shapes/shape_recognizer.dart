import 'dart:math' as math;
import 'dart:ui';

import '../../domain/shape_geometry.dart';
import 'polyline.dart';

/// Recognises a hand-drawn stroke as a clean shape ("hold to snap"),
/// where the hand drew it: same place, size and rotation.
///
/// * **Open** strokes become a [ShapeKind.arrow] when they end in a head
///   (wings on both sides of the shaft's tip), else a [ShapeKind.line] if
///   they are nearly straight already ([maxLineBow], [maxLineDetour]):
///   handwriting, curves and zig-zags are no line.
/// * **Closed** strokes (ending near their start, [maxGap]) are fitted
///   both as an ellipse and as a polygon; the better fit wins if it is
///   good enough (errors are measured as mean distance relative to the
///   shape's size; polygons with five or more corners must beat the
///   ellipse clearly). A polygon's corners are where its fitted sides
///   meet (not where the hand rounded them off), and a corner the fit
///   barely needs (a bowed side, the overshoot closing the loop) is
///   dropped. 3 corners → triangle; 4 →
///   diamond with diagonals along the axes, rectangle when right-angled
///   (axis-aligned when nearly so); up to 8 → polygon. Nearly round
///   ellipses become circles. Anything else (a scribble) is not recognised.
abstract final class ShapeRecognizer {
  /// Accepted mean fit error, relative to the bounding-box diagonal.
  static const double maxError = 0.035;

  /// A closed stroke's ends are at most this share of its bounding-box
  /// diagonal apart (a loop the hand did not quite finish still counts).
  static const double maxGap = 0.3;

  /// A line's points lie at most this share of its length off the chord
  /// between its ends…
  static const double maxLineBow = 0.08;

  /// … and its path is at most this many times as long as the chord.
  static const double maxLineDetour = 1.15;

  static ShapeGeometry? recognize(List<Offset> input) {
    final points = Polyline.dedupe(input);
    if (points.length < 2) return null;
    final bounds = Polyline.bounds(points);
    final diagonal = math.sqrt(bounds.width * bounds.width + bounds.height * bounds.height);
    if (diagonal == 0) return null;
    final length = Polyline.length(points);
    final gap = (points.last - points.first).distance;
    final closed = gap <= maxGap * diagonal && length >= 1.6 * diagonal;
    if (!closed) return _arrow(points, diagonal) ?? _line(points, length);
    return _closed(points, diagonal);
  }

  // ---------------------------------------------------------------------------
  // Open strokes

  static ShapeGeometry? _line(List<Offset> points, double length) {
    final a = points.first, b = points.last, chord = b - a;
    final span = chord.distance;
    if (span == 0 || length > maxLineDetour * span) return null;
    for (final p in points) {
      final off = (chord.dx * (p.dy - a.dy) - chord.dy * (p.dx - a.dx)).abs() / span;
      if (off > maxLineBow * span) return null;
    }
    return ShapeGeometry(ShapeKind.line, [a, b]);
  }

  static ShapeGeometry? _arrow(List<Offset> points, double diagonal) {
    final v = Polyline.simplify(points, 0.05 * diagonal);
    if (v.length < 4) return null;
    final tail = v[0], tip = v[1];
    final shaft = tip - tail;
    final shaftLength = shaft.distance;
    if (shaftLength < 0.5 * diagonal) return null;
    // The shaft itself is straight.
    final shaftEnd = points.indexOf(tip);
    if (_line(points.sublist(0, shaftEnd + 1), Polyline.length(points.sublist(0, shaftEnd + 1))) ==
        null) {
      return null;
    }
    var left = false, right = false;
    for (final p in v.skip(2)) {
      final d = p - tip;
      if (d.distance > 0.5 * shaftLength) return null; // not a head
      final side = shaft.dx * d.dy - shaft.dy * d.dx;
      // Wings point back along the shaft.
      if (d.dx * shaft.dx + d.dy * shaft.dy > 0.3 * d.distance * shaftLength) continue;
      if (side.abs() < 0.05 * d.distance * shaftLength) continue;
      if (side > 0) {
        left = true;
      } else {
        right = true;
      }
    }
    if (!left || !right) return null;
    return ShapeGeometry(ShapeKind.arrow, [tail, tip]);
  }

  // ---------------------------------------------------------------------------
  // Closed strokes

  static ShapeGeometry? _closed(List<Offset> points, double diagonal) {
    final loop = Polyline.resample(Polyline.trimOverlap(points), 96);
    final ellipse = _fitEllipse(loop);
    var corners = Polyline.corners(loop, 0.045 * diagonal, merge: 0.1 * diagonal);
    // More corners than a polygon has: a scribble.
    final polygon = corners.length >= 3 && corners.length <= 8;
    if (polygon) corners = _fewest(loop, corners, diagonal);
    final polygonError = polygon
        ? Polyline.meanDistanceToPolygon(loop, corners) / diagonal
        : double.infinity;
    final ellipseError = ellipse == null ? double.infinity : ellipse.error / diagonal;
    if (math.min(polygonError, ellipseError) > maxError) return null;
    // Noisy ellipses fit many-cornered polygons too; those must win clearly.
    final bias = corners.length >= 5 ? 0.7 : 1.0;
    if (ellipseError * bias <= polygonError) return ellipse!.shape;
    return _polygonShape(corners);
  }

  /// [corners] fitted to [loop] ([Polyline.fitCorners]), less any corner
  /// the fit barely needs: a bowed side or a closing overshoot can look
  /// like one more corner, which a shape with one corner fewer fits about
  /// as well (within [cornerSlack] of the diagonal, mean distance).
  static List<Offset> _fewest(List<Offset> loop, List<Offset> corners, double diagonal) {
    List<Offset> fit(List<Offset> c) => Polyline.fitCorners(loop, c, 0.2 * diagonal);
    var best = fit(corners);
    var error = Polyline.meanDistanceToPolygon(loop, best);
    while (best.length > 3) {
      List<Offset>? fewer;
      var fewerError = double.infinity;
      for (var i = 0; i < best.length; i++) {
        final c = fit([...best]..removeAt(i));
        final e = Polyline.meanDistanceToPolygon(loop, c);
        if (e < fewerError) {
          fewer = c;
          fewerError = e;
        }
      }
      if (fewerError > error + cornerSlack * diagonal) break;
      best = fewer!;
      error = fewerError;
    }
    return best;
  }

  /// How much worse (mean distance, share of the diagonal) a fit with one
  /// corner fewer may be and still be preferred.
  static const double cornerSlack = 0.004;

  static ShapeGeometry _polygonShape(List<Offset> corners) {
    if (corners.length == 3) return ShapeGeometry(ShapeKind.triangle, corners);
    if (corners.length == 4) {
      if (_axisDiagonals(corners)) {
        final r = Polyline.bounds(corners);
        return ShapeGeometry(ShapeKind.diamond, [
          r.topCenter,
          r.centerRight,
          r.bottomCenter,
          r.centerLeft,
        ]);
      }
      if (_rightAngled(corners)) return ShapeGeometry(ShapeKind.rectangle, _rectangle(corners));
    }
    return ShapeGeometry(ShapeKind.polygon, corners);
  }

  /// Whether a quadrilateral's diagonals run along the axes (within 10°),
  /// as a diamond's do.
  static bool _axisDiagonals(List<Offset> c) {
    bool along(Offset d) {
      final a = math.atan2(d.dy, d.dx).abs() % (math.pi / 2);
      return math.min(a, math.pi / 2 - a) < 10 * math.pi / 180;
    }

    final d1 = c[2] - c[0], d2 = c[3] - c[1];
    final perpendicular = (d1.dx * d2.dx + d1.dy * d2.dy).abs() < 0.2 * d1.distance * d2.distance;
    return along(d1) && along(d2) && perpendicular;
  }

  static bool _rightAngled(List<Offset> c) {
    for (var i = 0; i < 4; i++) {
      final a = c[(i + 3) % 4] - c[i], b = c[(i + 1) % 4] - c[i];
      final cos = (a.dx * b.dx + a.dy * b.dy) / (a.distance * b.distance);
      if (cos.abs() > math.sin(15 * math.pi / 180)) return false;
    }
    return true;
  }

  /// The best rectangle through 4 roughly right-angled corners: oriented
  /// along the longest side (snapped to the axes within 6°), each side
  /// midway between the two corners on it in that frame.
  static List<Offset> _rectangle(List<Offset> c) {
    var longest = c[1] - c[0];
    for (var i = 1; i < 4; i++) {
      final side = c[(i + 1) % 4] - c[i];
      if (side.distance > longest.distance) longest = side;
    }
    var angle = math.atan2(longest.dy, longest.dx);
    const quarter = math.pi / 2;
    angle -= (angle / quarter).round() * quarter; // into (-45°, 45°]
    if (angle.abs() < 6 * math.pi / 180) angle = 0;
    final centre = Polyline.centroid(c);
    final local = [for (final p in c) _rotate(p - centre, -angle)];
    final xs = [for (final p in local) p.dx]..sort();
    final ys = [for (final p in local) p.dy]..sort();
    final r = Rect.fromLTRB(
      (xs[0] + xs[1]) / 2,
      (ys[0] + ys[1]) / 2,
      (xs[2] + xs[3]) / 2,
      (ys[2] + ys[3]) / 2,
    );
    return [
      for (final p in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft])
        centre + _rotate(p, angle),
    ];
  }

  static ({ShapeGeometry shape, double error})? _fitEllipse(List<Offset> loop) {
    final mean = Polyline.centroid(loop);
    var sxx = 0.0, syy = 0.0, sxy = 0.0;
    for (final p in loop) {
      final d = p - mean;
      sxx += d.dx * d.dx;
      syy += d.dy * d.dy;
      sxy += d.dx * d.dy;
    }
    var angle = 0.5 * math.atan2(2 * sxy, sxx - syy);
    final local = [for (final p in loop) _rotate(p - mean, -angle)];
    final box = Polyline.bounds(local);
    var rx = box.width / 2, ry = box.height / 2;
    if (rx <= 0 || ry <= 0) return null;
    final centre = mean + _rotate(box.center, angle);
    var error = 0.0;
    for (final p in local) {
      final q = p - box.center;
      final rho = math.sqrt(math.pow(q.dx / rx, 2) + math.pow(q.dy / ry, 2));
      error += (rho - 1).abs();
    }
    error = error / local.length * math.sqrt(rx * ry);
    // Clean-ups: near-circles become circles, near-axis ellipses straight.
    if ((rx - ry).abs() <= 0.12 * math.max(rx, ry)) {
      rx = ry = (rx + ry) / 2;
      angle = 0;
    }
    const quarter = math.pi / 2;
    final snapped = (angle / quarter).round() * quarter;
    if ((angle - snapped).abs() < 8 * math.pi / 180) angle = snapped;
    final shape = ShapeGeometry(ShapeKind.ellipse, [
      centre,
      centre + _rotate(Offset(rx, 0), angle),
      centre + _rotate(Offset(0, ry), angle),
    ]);
    return (shape: shape, error: error);
  }

  static Offset _rotate(Offset v, double a) =>
      Offset(v.dx * math.cos(a) - v.dy * math.sin(a), v.dx * math.sin(a) + v.dy * math.cos(a));
}
