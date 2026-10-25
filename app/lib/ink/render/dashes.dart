import 'dart:math' as math;
import 'dart:ui';

/// [source] cut into dashes along its length ([dash] on, [gap] off), the
/// pattern running on across its curves and contours.
Path dashPath(Path source, {double dash = 6, double gap = 4}) {
  final dashes = Path();
  var drawing = true;
  var remaining = dash;
  for (final metric in source.computeMetrics()) {
    var at = 0.0;
    while (at < metric.length) {
      final step = math.min(remaining, metric.length - at);
      if (drawing) dashes.addPath(metric.extractPath(at, at + step), Offset.zero);
      at += step;
      remaining -= step;
      if (remaining <= 0) {
        drawing = !drawing;
        remaining = drawing ? dash : gap;
      }
    }
  }
  return dashes;
}
