import 'dart:math' as math;
import 'dart:ui';

/// Receives the segments of a stroke outline. [PathSink] builds a [Path];
/// tests record the segments to check their geometry exactly.
abstract interface class OutlineSink {
  void moveTo(double x, double y);
  void lineTo(double x, double y);
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3);

  /// An arc of the circle around ([cx], [cy]) from angle [start] sweeping
  /// [sweep] radians (negative = counter-clockwise on screen). It starts at
  /// the current point.
  void arc(double cx, double cy, double radius, double start, double sweep);
  void close();
}

/// Writes outline segments into [path].
class PathSink implements OutlineSink {
  PathSink(this.path);

  final Path path;

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) =>
      path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void arc(double cx, double cy, double radius, double start, double sweep) =>
      path.arcTo(Rect.fromCircle(center: Offset(cx, cy), radius: radius), start, sweep, false);

  @override
  void close() => path.close();
}

/// Adds a full circle to [sink], wound like stroke outlines.
void addCircle(OutlineSink sink, double cx, double cy, double r) {
  sink
    ..moveTo(cx + r, cy)
    ..arc(cx, cy, r, 0, -math.pi)
    ..arc(cx, cy, r, -math.pi, -math.pi)
    ..close();
}
