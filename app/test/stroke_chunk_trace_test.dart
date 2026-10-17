import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/stroke_chunks.dart';

/// `StrokeChunks.along` as it was before it was traced incrementally: the
/// reference the trace must match exactly.
Set<ChunkKey> _reference(List<StrokePoint> points, double width) {
  final pad = width;
  final keys = <ChunkKey>{};
  final bounds = Stroke.computeBounds(points, width);
  if (points.length == 1) {
    final p = points.single.offset;
    return ChunkGrid.rangeFor(Rect.fromCircle(center: p, radius: pad)).keys.toSet();
  }
  final range = ChunkGrid.rangeFor(bounds);
  if (range.count == 1) return {(x: range.minX, y: range.minY)};
  var pieces = 0.0;
  for (var i = 0; i + 1 < points.length && pieces <= 200000; i++) {
    pieces += (points[i + 1].offset - points[i].offset).distance / 128 + 1;
  }
  if (pieces > 200000) return range.keys.toSet();
  double toSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSq = ab.distanceSquared;
    if (lengthSq == 0) return (p - a).distance;
    final ap = p - a;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSq).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  for (var i = 0; i + 1 < points.length; i++) {
    final a = points[i].offset;
    final b = points[i + 1].offset;
    var stray = 0.0;
    for (var j = math.max(0, i - 6); j <= math.min(points.length - 1, i + 7); j++) {
      stray = math.max(stray, toSegment(points[j].offset, a, b));
    }
    final reach = pad + stray * 1.25 + 1;
    final n = math.max(1, ((b - a).distance / 128).ceil());
    for (var k = 0; k < n; k++) {
      final p = Offset.lerp(a, b, k / n)!;
      final q = Offset.lerp(a, b, (k + 1) / n)!;
      keys.addAll(ChunkGrid.rangeFor(Rect.fromPoints(p, q).inflate(reach).intersect(bounds)).keys);
    }
  }
  return keys;
}

void main() {
  test('traced as points arrive, a stroke gets exactly the chunks of its final points', () {
    final random = math.Random(11);
    for (var n = 0; n < 120; n++) {
      // Random walks and loops of all densities, many along chunk borders.
      final spacing = [1.0, 3.0, 20.0, 90.0, 300.0][n % 5];
      // At most ~20,000 long (the bounding box fallback lists its chunks).
      final count = math.min([1, 2, 5, 9, 40, 400, 3000][n % 7], 1 + 20000 ~/ spacing);
      final border = n.isEven;
      var p = border
          ? Offset(512.0 * random.nextInt(4), 512.0 * random.nextInt(4) - 3)
          : Offset(random.nextDouble() * 2000 - 1000, random.nextDouble() * 2000 - 1000);
      var angle = random.nextDouble() * 2 * math.pi;
      final points = <StrokePoint>[];
      for (var i = 0; i < count; i++) {
        points.add(StrokePoint(p.dx, p.dy, random.nextDouble()));
        angle += (random.nextDouble() - 0.5) * (border ? 0.3 : 2);
        p += Offset(math.cos(angle), math.sin(angle)) * spacing;
      }
      final width = [2.0, 8.0, 24.0][n % 3];
      final expected = _reference(points, width);
      expect(StrokeChunks.along(points, width), expected, reason: 'stroke $n');

      final trace = StrokeChunkTrace(width);
      final live = <StrokePoint>[];
      var i = 0;
      while (i < points.length) {
        final step = 1 + random.nextInt(n % 4 == 0 ? 1 : 30);
        for (var k = 0; k < step && i < points.length - 2; k++) {
          live.add(points[i++]);
        }
        if (i >= points.length - 2) break;
        trace.add(live);
      }
      // The end is added at the lift, its pressures settled.
      final last = [for (final q in points) StrokePoint(q.x, q.y, q.pressure / 2)];
      expect(trace.finish(last), expected, reason: 'stroke $n traced');
      expect(trace.bounds, Stroke.computeBounds(points, width), reason: 'stroke $n bounds');
    }
  });

  test('a pathological stroke traced falls back to its bounding box', () {
    final points = [
      for (var i = 0; i < 2000; i++) StrokePoint(i.isEven ? 0 : 100000, i * 10.0, 0.5),
    ];
    final trace = StrokeChunkTrace(2);
    for (var i = 1; i < points.length; i += 7) {
      trace.add(points.sublist(0, i));
    }
    expect(trace.finish(points), _reference(points, 2));
  });

  test('other points than the ones traced are refused', () {
    final points = [for (var i = 0; i < 40; i++) StrokePoint(i * 30.0, 0, 0.5)];
    final trace = StrokeChunkTrace(2)..add(points);
    expect(
      () => trace.finish([for (final p in points) StrokePoint(p.x, 5, 0.5)]),
      throwsStateError,
    );
  });
}
