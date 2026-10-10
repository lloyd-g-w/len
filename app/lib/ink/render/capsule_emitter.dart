import 'dart:math' as math;

import 'centerline.dart';
import 'outline_sink.dart';

/// Turns a [Centerline] into a filled outline: the union of "capsules" —
/// the convex hull of the circles at each pair of consecutive samples.
///
/// Why capsules:
///  * **Stable while drawing.** Each capsule depends only on its two
///    samples, so new input at the pen tip only *adds* geometry; ink
///    behind the tip never re-shapes (no flicker at bends or cusps).
///  * **No special cases.** Cusps, hairpins and self-overlaps are just
///    overlapping capsules; the non-zero fill unions them exactly.
///  * **Smooth edges at any zoom.** Neighbouring capsules share a circle,
///    so the outer side of a bend is line–arc–line (tangent-continuous);
///    the inner side meets at the tiny turn angle of one sample step.
///
/// Every capsule is wound the same way. Nearly collinear runs of samples
/// with nearly equal radii are merged into one capsule, which keeps paths
/// small without visible change.
class CapsuleEmitter {
  CapsuleEmitter(this.line, {required this.flatCaps});

  final Centerline line;

  /// Square ends (highlighter) at the stroke's two ends.
  final bool flatCaps;

  /// Merge tolerances: total turn (radians) and relative radius change a
  /// merged capsule may span.
  static const double _mergeTurn = 0.02;
  static const double _mergeRadius = 0.01;

  void emit(OutlineSink sink) {
    final n = line.length;
    if (n == 0) return;
    if (n == 1) return addCircle(sink, line.x[0], line.y[0], line.r[0]);
    final keys = _keySamples();
    for (var k = 1; k < keys.length; k++) {
      _capsule(
        sink,
        keys[k - 1],
        keys[k],
        flatStart: flatCaps && k == 1,
        flatEnd: flatCaps && k == keys.length - 1,
      );
    }
  }

  /// Sample indices kept as capsule end points.
  List<int> _keySamples() {
    final x = line.x, y = line.y, r = line.r;
    final n = line.length;
    final keys = <int>[0];
    var dirX = 0.0, dirY = 0.0;
    for (var i = 1; i < n; i++) {
      final from = keys.last;
      final dx = x[i] - x[from], dy = y[i] - y[from];
      final d = math.sqrt(dx * dx + dy * dy);
      if (i == from + 1 || d == 0) {
        if (d > 0) {
          dirX = dx / d;
          dirY = dy / d;
        }
        if (i == n - 1) keys.add(i);
        continue;
      }
      // Can [from]..[i] still be one capsule? Its direction must stay within
      // the turn tolerance of where the run started, and radii stay level.
      final cos = (dx * dirX + dy * dirY) / d;
      final rFrom = r[from];
      final level = (r[i] - rFrom).abs() <= _mergeRadius * rFrom + 1e-4;
      if (cos < math.cos(_mergeTurn) || !level) {
        keys.add(i - 1);
        final sx = x[i] - x[i - 1], sy = y[i] - y[i - 1];
        final sd = math.sqrt(sx * sx + sy * sy);
        if (sd > 0) {
          dirX = sx / sd;
          dirY = sy / sd;
        }
      }
      if (i == n - 1) keys.add(i);
    }
    return keys;
  }

  /// The convex hull of the circles at samples [i] and [j].
  void _capsule(OutlineSink sink, int i, int j, {bool flatStart = false, bool flatEnd = false}) {
    final x1 = line.x[i], y1 = line.y[i], r1 = line.r[i];
    final x2 = line.x[j], y2 = line.y[j], r2 = line.r[j];
    final dx = x2 - x1, dy = y2 - y1;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d <= (r1 - r2).abs() + 1e-9) {
      // One circle contains the other.
      return r1 >= r2 ? addCircle(sink, x1, y1, r1) : addCircle(sink, x2, y2, r2);
    }
    final ux = dx / d, uy = dy / d;
    // External tangents touch each circle at angle ±(π/2 − a) from u,
    // where sin a = (r1 − r2) / d.
    final s = (r1 - r2) / d;
    final c = math.sqrt(1 - s * s);
    final nx = -uy, ny = ux;
    final lx = ux * s + nx * c, ly = uy * s + ny * c; // "left" tangent direction
    final rx = ux * s - nx * c, ry = uy * s - ny * c; // "right"
    final theta = math.atan2(uy, ux);
    final a = math.asin(s);

    sink.moveTo(x1 + r1 * lx, y1 + r1 * ly);
    sink.lineTo(x2 + r2 * lx, y2 + r2 * ly);
    if (flatEnd) {
      sink.lineTo(x2 + r2 * rx, y2 + r2 * ry);
    } else {
      // Around the front of circle 2: from +(π/2 − a) to −(π/2 − a).
      sink.arc(x2, y2, r2, theta + math.pi / 2 - a, -(math.pi - 2 * a));
    }
    sink.lineTo(x1 + r1 * rx, y1 + r1 * ry);
    if (flatStart) {
      sink.lineTo(x1 + r1 * lx, y1 + r1 * ly);
    } else {
      // Around the back of circle 1: from −(π/2 − a) on through π to +(π/2 − a).
      sink.arc(x1, y1, r1, theta - math.pi / 2 + a, -(math.pi + 2 * a));
    }
    sink.close();
  }
}
