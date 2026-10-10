import 'dart:math' as math;
import 'dart:ui';

import 'polyline.dart';
import 'shape_builder.dart';
import 'shape_kind.dart';

/// A recognised shape: its kind and clean outline vertices (closed
/// outlines repeat their first vertex).
typedef RecognizedShape = ({ShapeKind kind, List<Offset> outline});

/// Recognises a hand-drawn stroke as a clean shape ("hold to snap").
///
/// * **Open** strokes become a [ShapeKind.line] — or an [ShapeKind.arrow]
///   when they end in a head (wings on both sides of the shaft's tip).
/// * **Closed** strokes (ending near their start) are fitted both as an
///   ellipse and as a polygon; the better fit wins if it is good enough
///   (errors are measured as mean distance relative to the shape's size;
///   polygons with five or more corners must beat the ellipse clearly).
///   Polygons are cleaned up: 3 corners → triangle, 4 right-angled
///   corners → rectangle (axis-aligned when nearly so), up to 8 corners →
///   polygon. Nearly round ellipses become circles. Anything else (a
///   scribble) is not recognised.
abstract final class ShapeRecognizer {
  /// Accepted mean fit error, relative to the bounding-box diagonal.
  static const double maxError = 0.035;

  static RecognizedShape? recognize(List<Offset> input) {
    final points = Polyline.dedupe(input);
    if (points.length < 2) return null;
    final bounds = Polyline.bounds(points);
    final diagonal = math.sqrt(bounds.width * bounds.width + bounds.height * bounds.height);
    if (diagonal == 0) return null;
    final length = Polyline.length(points);
    final gap = (points.last - points.first).distance;
    final closed = gap <= 0.22 * diagonal && length >= 1.6 * diagonal;
    if (!closed) {
      return _arrow(points, diagonal) ??
          (kind: ShapeKind.line, outline: [points.first, points.last]);
    }
    return _closed(points, diagonal);
  }

  // ---------------------------------------------------------------------------
  // Open strokes

  static RecognizedShape? _arrow(List<Offset> points, double diagonal) {
    final v = Polyline.simplify(points, 0.05 * diagonal);
    if (v.length < 4) return null;
    final tail = v[0], tip = v[1];
    final shaft = tip - tail;
    final shaftLength = shaft.distance;
    if (shaftLength < 0.5 * diagonal) return null;
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
    return (kind: ShapeKind.arrow, outline: ShapeBuilder.arrow(tail, tip));
  }

  // ---------------------------------------------------------------------------
  // Closed strokes

  static RecognizedShape? _closed(List<Offset> points, double diagonal) {
    final loop = Polyline.resample(Polyline.trimOverlap(points), 96);
    final ellipse = _fitEllipse(loop);
    final corners = Polyline.corners(loop, 0.045 * diagonal);
    final polygonError = corners.length >= 3 && corners.length <= 8
        ? Polyline.meanDistanceToPolygon(loop, corners) / diagonal
        : double.infinity;
    final ellipseError = ellipse == null ? double.infinity : ellipse.error / diagonal;
    if (math.min(polygonError, ellipseError) > maxError) return null;
    // Noisy ellipses fit many-cornered polygons too; those must win clearly.
    final bias = corners.length >= 5 ? 0.7 : 1.0;
    if (ellipseError * bias <= polygonError) return _ellipseShape(ellipse!);
    return _polygonShape(corners, loop);
  }

  static RecognizedShape _polygonShape(List<Offset> corners, List<Offset> loop) {
    if (corners.length == 3) {
      return (kind: ShapeKind.triangle, outline: [...corners, corners.first]);
    }
    if (corners.length == 4 && _rightAngled(corners)) {
      return (kind: ShapeKind.rectangle, outline: _rectangle(corners, loop));
    }
    return (kind: ShapeKind.polygon, outline: [...corners, corners.first]);
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
  /// along the longest side (snapped to the axes within 6°), spanning the
  /// drawn points' extent in that frame.
  static List<Offset> _rectangle(List<Offset> c, List<Offset> loop) {
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
    final r = Polyline.bounds(local);
    return [
      for (final p in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft, r.topLeft])
        centre + _rotate(p, angle),
    ];
  }

  static ({Offset centre, double rx, double ry, double angle, double error})? _fitEllipse(
    List<Offset> loop,
  ) {
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
    return (centre: centre, rx: rx, ry: ry, angle: angle, error: error);
  }

  static RecognizedShape _ellipseShape(
    ({Offset centre, double rx, double ry, double angle, double error}) e,
  ) => (
    kind: ShapeKind.ellipse,
    outline: ShapeBuilder.ellipse(e.centre, e.rx, e.ry, angle: e.angle),
  );

  static Offset _rotate(Offset v, double a) =>
      Offset(v.dx * math.cos(a) - v.dy * math.sin(a), v.dx * math.sin(a) + v.dy * math.cos(a));
}
