import 'dart:math' as math;
import 'dart:ui';

/// Draws [points] as a dashed polyline (closed back to the start with
/// [close]); the pattern continues across vertices.
void drawDashed(
  Canvas canvas,
  List<Offset> points,
  Paint paint, {
  bool close = false,
  double dash = 6,
  double gap = 4,
}) {
  if (points.length < 2) return;
  final pts = close ? [...points, points.first] : points;
  final path = Path();
  var drawing = true;
  var remaining = dash;
  for (var i = 1; i < pts.length; i++) {
    var a = pts[i - 1];
    final b = pts[i];
    var length = (b - a).distance;
    while (length > 0) {
      final step = math.min(remaining, length);
      final next = Offset.lerp(a, b, step / length)!;
      if (drawing) {
        path
          ..moveTo(a.dx, a.dy)
          ..lineTo(next.dx, next.dy);
      }
      a = next;
      length -= step;
      remaining -= step;
      if (remaining <= 0) {
        drawing = !drawing;
        remaining = drawing ? dash : gap;
      }
    }
  }
  canvas.drawPath(path, paint);
}
