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

  /// Most pieces examined before falling back to the bounding box.
  static const double _maxPieces = 200000;

  /// The chunks of a committed stroke (memoised per instance; read-only).
  /// A filled shape ([Stroke.fill]) covers its inside too: every chunk its
  /// bounds overlap.
  static Set<ChunkKey> of(Stroke stroke) => _memo[stroke] ??= Set.unmodifiable(
    stroke.fill != null
        ? ChunkGrid.rangeFor(stroke.bounds).keys.toSet()
        : along(stroke.points, stroke.width),
  );

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
    // Within one chunk (most handwriting): that chunk, without measuring
    // every segment (loading a page indexes thousands of strokes at once).
    final range = ChunkGrid.rangeFor(bounds);
    if (range.count == 1) return {(x: range.minX, y: range.minY)};
    // A pathological stroke (very long zigzags) would take too many
    // pieces; its bounding box is always a valid (if coarser) answer.
    var pieces = 0.0;
    for (var i = 0; i + 1 < points.length && pieces <= _maxPieces; i++) {
      pieces += (points[i + 1].offset - points[i].offset).distance / _piece + 1;
    }
    if (pieces > _maxPieces) return ChunkGrid.rangeFor(bounds).keys.toSet();
    // In plain doubles (no offsets, rects or ranges per piece: a commit of
    // many long lines spent most of its time here), skipping a piece in the
    // chunks of the one before it and stopping once every chunk of the
    // bounds is in.
    const size = ChunkGrid.size;
    final (left, top, right, bottom) = (bounds.left, bounds.top, bounds.right, bounds.bottom);
    var last = (minX: 0, minY: 0, maxX: -1, maxY: -1);
    for (var i = 0; i + 1 < points.length && keys.length < range.count; i++) {
      final ax = points[i].x, ay = points[i].y;
      final bx = points[i + 1].x, by = points[i + 1].y;
      final reach = pad + _stray(points, i, ax, ay, bx, by) * 1.25 + 1;
      final dx = bx - ax, dy = by - ay;
      final pieces = math.max(1, (math.sqrt(dx * dx + dy * dy) / _piece).ceil());
      for (var k = 0; k < pieces; k++) {
        // As Offset.lerp, Rect.fromPoints, inflate and intersect would.
        final t0 = k / pieces, t1 = (k + 1) / pieces;
        final px = ax * (1.0 - t0) + bx * t0, py = ay * (1.0 - t0) + by * t0;
        final qx = ax * (1.0 - t1) + bx * t1, qy = ay * (1.0 - t1) + by * t1;
        final minX = (math.max(math.min(px, qx) - reach, left) / size).floor();
        final minY = (math.max(math.min(py, qy) - reach, top) / size).floor();
        final maxX = (math.min(math.max(px, qx) + reach, right) / size).floor();
        final maxY = (math.min(math.max(py, qy) + reach, bottom) / size).floor();
        if (minX == last.minX && minY == last.minY && maxX == last.maxX && maxY == last.maxY) {
          continue;
        }
        last = (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
        for (var y = minY; y <= maxY; y++) {
          for (var x = minX; x <= maxX; x++) {
            keys.add((x: x, y: y));
          }
        }
      }
    }
    return keys;
  }

  /// How far the samples around segment [i] (from a to b) lie from it
  /// (they pull the smoothed curve sideways by at most this much).
  static double _stray(
    List<StrokePoint> points,
    int i,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final from = math.max(0, i - _window);
    final to = math.min(points.length - 1, i + 1 + _window);
    final abx = bx - ax, aby = by - ay;
    final lengthSq = abx * abx + aby * aby;
    var stray = 0.0;
    for (var j = from; j <= to; j++) {
      // The distance to the segment.
      final apx = points[j].x - ax, apy = points[j].y - ay;
      var dx = apx, dy = apy;
      if (lengthSq != 0) {
        final t = ((apx * abx + apy * aby) / lengthSq).clamp(0.0, 1.0);
        dx = points[j].x - (ax + abx * t);
        dy = points[j].y - (ay + aby * t);
      }
      stray = math.max(stray, math.sqrt(dx * dx + dy * dy));
    }
    return stray;
  }
}

/// The chunks a surface element (text box, image) is indexed in: every
/// chunk its axis-aligned bounds overlap. Like [StrokeChunks], shared by the
/// storage index (`element_chunks`) and the in-memory index.
abstract final class ElementChunks {
  static Iterable<ChunkKey> of(SurfaceElement element) => ChunkGrid.rangeFor(element.bounds).keys;
}
