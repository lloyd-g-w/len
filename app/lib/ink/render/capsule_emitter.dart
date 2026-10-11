import 'dart:math' as math;

import 'outline_sink.dart';

/// Emits a *capsule*: the convex hull of the circles at ([x1], [y1]) with
/// radius [r1] and ([x2], [y2]) with radius [r2], wound like every other
/// outline contour (so the non-zero fill unions overlapping pieces).
///
/// `RibbonEmitter` draws the segments where a stroke's envelope folds
/// (cusps, bends tighter than the radius) as capsules: exact, and with no
/// special cases.
void emitCapsule(
  OutlineSink sink,
  double x1,
  double y1,
  double r1,
  double x2,
  double y2,
  double r2,
) {
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
  sink
    ..moveTo(x1 + r1 * lx, y1 + r1 * ly)
    ..lineTo(x2 + r2 * lx, y2 + r2 * ly)
    // Around the front of circle 2: from +(π/2 − a) to −(π/2 − a).
    ..arc(x2, y2, r2, theta + math.pi / 2 - a, -(math.pi - 2 * a))
    ..lineTo(x1 + r1 * rx, y1 + r1 * ry)
    // Around the back of circle 1: from −(π/2 − a) on through π to +(π/2 − a).
    ..arc(x1, y1, r1, theta - math.pi / 2 + a, -(math.pi + 2 * a))
    ..close();
}
