import 'dart:math' as math;
import 'dart:ui';

import '../../domain/stroke.dart';
import '../stroke_hit_test.dart';

/// Geometry of the pixel (partial) eraser: cuts the part of a stroke under
/// the eraser out and keeps what survives as new strokes.
abstract final class StrokeSplitter {
  /// Caps the points inserted into one segment (very long straight lines).
  static const int _maxInserted = 1024;

  /// Erases the part of [stroke] within [radius] of the segment [a]→[b].
  ///
  /// Returns null when nothing is erased, otherwise the surviving fragments
  /// (possibly none), each a new stroke with an id from [newId]. Fragments
  /// keep the original's creation time and style, so they paint in the
  /// same order and look.
  static List<Stroke>? erase(
    Stroke stroke,
    Offset a,
    Offset b,
    double radius, {
    required String Function() newId,
  }) {
    if (!StrokeHitTest.sweepHits(stroke, a, b, radius)) return null;
    // Points are cut where the eraser touches the ink's edge (which depends
    // on the pressure there), so fragment end caps line up with the eraser
    // circle.
    bool erased(StrokePoint p) {
      final reach = radius + StrokeHitTest.inkRadius(stroke, p);
      return StrokeHitTest.segmentDistSq(p.offset, p.offset, a, b) <= reach * reach;
    }

    if (stroke.points.length == 1) return erased(stroke.points.single) ? const [] : null;

    // The ink is never wider than the nominal width on either side.
    final maxReach = radius + stroke.width;
    final points = _densify(
      stroke.points,
      a,
      b,
      maxReach * maxReach,
      step: math.max(radius / 3, 0.2),
    );
    final keep = [for (final p in points) !erased(p)];
    if (!keep.contains(false)) return null;

    final fragments = <Stroke>[];
    var start = -1;
    for (var i = 0; i <= points.length; i++) {
      final kept = i < points.length && keep[i];
      if (kept && start < 0) start = i;
      if (!kept && start >= 0) {
        if (i - start >= 2) {
          fragments.add(stroke.withPoints(points.sublist(start, i), id: newId()));
        }
        start = -1;
      }
    }
    return fragments;
  }

  /// Inserts interpolated points (every [step] units) into the segments
  /// that pass within reach of the eraser, so the cut follows the eraser
  /// closely even where the input was sampled sparsely.
  static List<StrokePoint> _densify(
    List<StrokePoint> points,
    Offset a,
    Offset b,
    double reachSq, {
    required double step,
  }) {
    final out = <StrokePoint>[points.first];
    for (var i = 1; i < points.length; i++) {
      final p0 = points[i - 1], p1 = points[i];
      final length = (p1.offset - p0.offset).distance;
      final near = StrokeHitTest.segmentDistSq(p0.offset, p1.offset, a, b) <= reachSq;
      if (near && length > step) {
        final n = math.min((length / step).ceil(), _maxInserted);
        for (var k = 1; k < n; k++) {
          final t = k / n;
          out.add(
            StrokePoint(
              p0.x + (p1.x - p0.x) * t,
              p0.y + (p1.y - p0.y) * t,
              p0.pressure + (p1.pressure - p0.pressure) * t,
            ),
          );
        }
      }
      out.add(p1);
    }
    return out;
  }
}
