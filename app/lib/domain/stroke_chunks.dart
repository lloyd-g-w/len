import 'dart:math' as math;
import 'dart:ui';

import 'chunk_grid.dart';
import 'stroke.dart';
import 'surface_element.dart';

/// The chunks a stroke's ink actually passes through.
///
/// A long diagonal stroke's bounding box covers many chunks it never
/// touches; indexing only the chunks along its path keeps the chunk index
/// sparse (fewer rows, fewer chunk pictures to rebuild, fewer strokes to
/// load per chunk). The storage index (`stroke_chunks`) and the in-memory
/// `SpatialIndex` both use this, so they always agree.
///
/// The result is conservative: the rendered outline smooths positions over
/// a few neighbouring samples and adds up to [Stroke.width] of thickness,
/// so each segment is widened by the stroke's padding plus how far nearby
/// samples stray from it.
abstract final class StrokeChunks {
  static final Expando<Set<ChunkKey>> _memo = Expando('stroke chunks');

  /// Neighbouring samples that can influence the rendered centre line of a
  /// segment (position smoothing window plus spline neighbours).
  static const int _window = 6;

  /// Longest piece a segment is cut into before taking its bounding box.
  static const double _piece = ChunkGrid.size / 4;

  /// The chunks of a committed stroke (memoised per instance; read-only).
  static Set<ChunkKey> of(Stroke stroke) =>
      _memo[stroke] ??= Set.unmodifiable(along(stroke.points, stroke.width));

  /// The chunks touched by ink of width [width] drawn through [points].
  static Set<ChunkKey> along(List<StrokePoint> points, double width) {
    final pad = width; // Same generous padding as [Stroke.computeBounds].
    final keys = <ChunkKey>{};
    // Never more than the bounding box (which old index rows used).
    final bounds = Stroke.computeBounds(points, width);
    if (points.length == 1) {
      final p = points.single.offset;
      keys.addAll(ChunkGrid.rangeFor(Rect.fromCircle(center: p, radius: pad)).keys);
      return keys;
    }
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i].offset;
      final b = points[i + 1].offset;
      final reach = pad + _stray(points, i, a, b) * 1.25 + 1;
      final pieces = math.max(1, ((b - a).distance / _piece).ceil());
      for (var k = 0; k < pieces; k++) {
        final p = Offset.lerp(a, b, k / pieces)!;
        final q = Offset.lerp(a, b, (k + 1) / pieces)!;
        final piece = Rect.fromPoints(p, q).inflate(reach).intersect(bounds);
        keys.addAll(ChunkGrid.rangeFor(piece).keys);
      }
    }
    return keys;
  }

  /// How far the samples around segment [i] lie from it (they pull the
  /// smoothed curve sideways by at most this much).
  static double _stray(List<StrokePoint> points, int i, Offset a, Offset b) {
    final from = math.max(0, i - _window);
    final to = math.min(points.length - 1, i + 1 + _window);
    var stray = 0.0;
    for (var j = from; j <= to; j++) {
      stray = math.max(stray, _distanceToSegment(points[j].offset, a, b));
    }
    return stray;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSq = ab.distanceSquared;
    if (lengthSq == 0) return (p - a).distance;
    final ap = p - a;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSq).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }
}

/// The chunks a surface element (text box, image) is indexed in: every
/// chunk its axis-aligned bounds overlap. Like [StrokeChunks], shared by the
/// storage index (`element_chunks`) and the in-memory index.
abstract final class ElementChunks {
  static Iterable<ChunkKey> of(SurfaceElement element) => ChunkGrid.rangeFor(element.bounds).keys;
}
