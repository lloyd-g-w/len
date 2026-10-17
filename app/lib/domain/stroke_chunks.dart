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
  static Set<ChunkKey> along(List<StrokePoint> points, double width) =>
      StrokeChunkTrace(width, bounds: Stroke.computeBounds(points, width)).finish(points);

  /// Records [keys] as the chunks of [stroke] (as [of] would find them,
  /// e.g. traced while it was drawn, [StrokeChunkTrace]).
  static void adopt(Stroke stroke, Set<ChunkKey> keys) => _memo[stroke] = Set.unmodifiable(keys);

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

/// [StrokeChunks.along] built as a stroke's points arrive: each segment is
/// traced once the samples that can pull it sideways are known, so the
/// chunks of a long stroke are ready at pen-up (only its last segments are
/// left). Gives exactly what [StrokeChunks.along] gives for the final
/// points, as long as the points [add]ed are a prefix of them.
class StrokeChunkTrace {
  /// Traces ink of [width]; [bounds] are the stroke's final bounds
  /// ([Stroke.computeBounds]), when known up front.
  StrokeChunkTrace(this.width, {Rect? bounds}) : _final = bounds;

  /// The ink's width.
  final double width;

  /// The stroke's bounds, if known up front.
  final Rect? _final;

  final Set<ChunkKey> _keys = {};

  /// Pieces whose chunks may still grow with the stroke's bounds (before
  /// clipping to them).
  final List<Rect> _pending = [];

  /// Points seen (their bounds are in [_minX]…), segments traced.
  int _seen = 0, _traced = 0;
  Offset? _last;
  double _minX = double.infinity, _minY = double.infinity;
  double _maxX = double.negativeInfinity, _maxY = double.negativeInfinity;

  /// Pieces counted as [StrokeChunks.along] counts them; past its limit
  /// the stroke is indexed by its bounding box.
  double _pieces = 0;
  ChunkRange? _lastRange;

  /// Traces the segments of [points] (the stroke so far, the points added
  /// before unchanged) whose neighbourhood is complete.
  void add(List<StrokePoint> points) {
    _see(points);
    _trace(points, points.length - 1 - StrokeChunks._window);
  }

  /// Whether [points] may [finish] this trace: they begin with the points
  /// [add]ed (checked by their count and last position).
  bool follows(List<StrokePoint> points) =>
      points.length >= _seen && (_last == null || points[_seen - 1].offset == _last);

  /// The chunks of the stroke whose points are [points] (the points
  /// [add]ed, plus any more; pressures may differ, positions not).
  Set<ChunkKey> finish(List<StrokePoint> points) {
    if (!follows(points)) throw StateError('Not the points traced');
    _see(points);
    final bounds = _bounds;
    if (points.length == 1) {
      final p = points.single.offset;
      return ChunkGrid.rangeFor(Rect.fromCircle(center: p, radius: width)).keys.toSet();
    }
    // Within one chunk (most handwriting): that chunk.
    final range = ChunkGrid.rangeFor(bounds);
    if (range.count == 1) return {(x: range.minX, y: range.minY)};
    _trace(points, points.length - 1);
    // A pathological stroke (very long zigzags) would take too many
    // pieces; its bounding box is always a valid (if coarser) answer.
    if (_pieces > StrokeChunks._maxPieces) return range.keys.toSet();
    for (final piece in _pending) {
      _addRange(ChunkGrid.rangeFor(piece.intersect(bounds)));
    }
    _pending.clear();
    return _keys;
  }

  /// The bounds of the points seen ([Stroke.computeBounds]): the
  /// stroke's, once [finish]ed.
  Rect get bounds => _bounds;
  Rect get _bounds =>
      _final ?? Rect.fromLTRB(_minX - width, _minY - width, _maxX + width, _maxY + width);

  void _see(List<StrokePoint> points) {
    for (var i = _final == null ? _seen : points.length; i < points.length; i++) {
      final p = points[i];
      if (p.x < _minX) _minX = p.x;
      if (p.y < _minY) _minY = p.y;
      if (p.x > _maxX) _maxX = p.x;
      if (p.y > _maxY) _maxY = p.y;
    }
    _seen = points.length;
    if (_seen > 0) _last = points[_seen - 1].offset;
  }

  /// Traces segments up to (not including) [end].
  void _trace(List<StrokePoint> points, int end) {
    if (_traced >= end) return;
    final pad = width;
    final bounds = _bounds;
    for (var i = _traced; i < end; i++) {
      final a = points[i].offset;
      final b = points[i + 1].offset;
      final length = (b - a).distance;
      _pieces += length / StrokeChunks._piece + 1;
      if (_pieces > StrokeChunks._maxPieces) break;
      final reach = pad + StrokeChunks._stray(points, i, a, b) * 1.25 + 1;
      final pieces = math.max(1, (length / StrokeChunks._piece).ceil());
      for (var k = 0; k < pieces; k++) {
        final p = Offset.lerp(a, b, k / pieces)!;
        final q = Offset.lerp(a, b, (k + 1) / pieces)!;
        final piece = Rect.fromPoints(p, q).inflate(reach);
        final clipped = ChunkGrid.rangeFor(piece.intersect(bounds));
        _addRange(clipped);
        if (_final == null) _hold(piece, clipped);
      }
    }
    _traced = end;
  }

  /// Keeps [piece] for [finish] if the stroke's bounds, clipping it to
  /// [clipped] so far, may still grow to let it reach chunks not found yet.
  void _hold(Rect piece, ChunkRange clipped) {
    final whole = ChunkGrid.rangeFor(piece);
    if (whole == clipped) return;
    for (var y = whole.minY; y <= whole.maxY; y++) {
      for (var x = whole.minX; x <= whole.maxX; x++) {
        if (!_keys.contains((x: x, y: y))) return _pending.add(piece);
      }
    }
  }

  void _addRange(ChunkRange range) {
    if (range == _lastRange) return;
    _lastRange = range;
    for (var y = range.minY; y <= range.maxY; y++) {
      for (var x = range.minX; x <= range.maxX; x++) {
        _keys.add((x: x, y: y));
      }
    }
  }
}

/// The chunks a surface element (text box, image) is indexed in: every
/// chunk its axis-aligned bounds overlap. Like [StrokeChunks], shared by the
/// storage index (`element_chunks`) and the in-memory index.
abstract final class ElementChunks {
  static Iterable<ChunkKey> of(SurfaceElement element) => ChunkGrid.rangeFor(element.bounds).keys;
}
