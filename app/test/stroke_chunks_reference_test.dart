import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/stroke_chunks.dart';

/// [StrokeChunks.along] as it was written with offsets and rects: the
/// plain-double version must give the very same chunks (the storage index
/// and the in-memory one agree only if every version computes the same).
Set<ChunkKey> _reference(List<StrokePoint> points, double width) {
  final keys = <ChunkKey>{};
  final bounds = Stroke.computeBounds(points, width);
  for (var i = 0; i + 1 < points.length; i++) {
    final a = points[i].offset, b = points[i + 1].offset;
    var stray = 0.0;
    for (var j = math.max(0, i - 6); j <= math.min(points.length - 1, i + 7); j++) {
      final p = points[j].offset, ab = b - a;
      final lengthSq = ab.distanceSquared;
      if (lengthSq == 0) {
        stray = math.max(stray, (p - a).distance);
        continue;
      }
      final ap = p - a;
      final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSq).clamp(0.0, 1.0);
      stray = math.max(stray, (p - (a + ab * t)).distance);
    }
    final reach = width + stray * 1.25 + 1;
    final pieces = math.max(1, ((b - a).distance / (ChunkGrid.size / 4)).ceil());
    for (var k = 0; k < pieces; k++) {
      final p = Offset.lerp(a, b, k / pieces)!, q = Offset.lerp(a, b, (k + 1) / pieces)!;
      keys.addAll(ChunkGrid.rangeFor(Rect.fromPoints(p, q).inflate(reach).intersect(bounds)).keys);
    }
  }
  return keys;
}

void main() {
  test('along gives the chunks the offset-and-rect version gave', () {
    final random = math.Random(7);
    double nearEdge() =>
        (random.nextInt(8) - 4) * ChunkGrid.size + (random.nextDouble() - 0.5) * 40;
    for (var n = 0; n < 2000; n++) {
      // Walks of all lengths and step sizes starting near chunk edges.
      final step = [2.0, 20.0, 150.0, 900.0][n % 4];
      var x = nearEdge(), y = nearEdge();
      final points = <StrokePoint>[
        for (var i = 0; i < 2 + random.nextInt(120); i++)
          StrokePoint(
            x += (random.nextDouble() - 0.5) * step,
            y += (random.nextDouble() - 0.5) * step,
            0.5,
          ),
      ];
      if (n % 9 == 0) points.add(points.last); // A repeated sample.
      final width = 1 + random.nextDouble() * 30;
      expect(StrokeChunks.along(points, width), _reference(points, width), reason: 'walk $n');
    }
  });
}
