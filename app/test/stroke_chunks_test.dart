import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/stroke_chunks.dart';
import 'package:len/ink/render/stroke_renderer.dart';
import 'package:len/ink/spatial_index.dart';
import 'package:len/ink/surface_model.dart';

Stroke _stroke(
  String id,
  List<Offset> points, {
  double width = 3,
  InkTool tool = InkTool.ballpoint,
  StrokeStyle? style,
  double Function(int i)? pressure,
}) => Stroke(
  id: id,
  surfaceId: 's',
  tool: tool,
  color: 0xFF000000,
  width: width,
  style: style,
  points: [
    for (var i = 0; i < points.length; i++)
      StrokePoint(points[i].dx, points[i].dy, pressure?.call(i) ?? 0.5),
  ],
  createdAt: 1,
);

/// Chunks the rendered outline of [stroke] reaches, sampled along it.
Set<ChunkKey> _renderedChunks(Stroke stroke) {
  final keys = <ChunkKey>{};
  for (final metric in StrokeRenderer.pathOf(stroke).computeMetrics()) {
    for (var d = 0.0; d <= metric.length; d += 2) {
      final p = metric.getTangentForOffset(d)!.position;
      keys.add(ChunkGrid.keyAt(p.dx, p.dy));
    }
  }
  return keys;
}

void main() {
  group('StrokeChunks', () {
    test('a long diagonal indexes its path, not its bounding box', () {
      final line = _stroke('d', [const Offset(0, 0), const Offset(5000, 5000)]);
      final keys = StrokeChunks.of(line);
      final box = ChunkGrid.rangeFor(line.bounds).count;
      expect(box, 121); // 11 × 11 chunks (the padding reaches past 5120)
      expect(keys.length, lessThan(45));
      expect(keys, containsAll([(x: 0, y: 0), (x: 5, y: 5), (x: 9, y: 9)]));
      expect(keys, isNot(contains((x: 9, y: 0))));
    });

    test('a dot covers its own chunk (and neighbours it reaches)', () {
      final dot = _stroke('p', [const Offset(511, 100)], width: 4);
      expect(StrokeChunks.of(dot), {(x: 0, y: 0), (x: 1, y: 0)});
    });

    test('always covers every chunk the rendered ink reaches', () {
      final random = math.Random(7);
      for (var n = 0; n < 60; n++) {
        // Zig-zags with sparse and dense samples, strong smoothing and
        // pressure, crossing chunk borders at all angles.
        final spacing = [3.0, 20.0, 90.0, 300.0][n % 4];
        var p = Offset(random.nextDouble() * 2000 - 1000, random.nextDouble() * 2000 - 1000);
        final points = <Offset>[p];
        for (var i = 0; i < 40; i++) {
          final angle = random.nextDouble() * 2 * math.pi;
          p += Offset(math.cos(angle), math.sin(angle)) * spacing;
          points.add(p);
        }
        final stroke = _stroke(
          'z$n',
          points,
          width: [2.0, 8.0, 24.0][n % 3],
          tool: InkTool.pens[n % InkTool.pens.length],
          style: StrokeStyle.defaultsFor(InkTool.ballpoint).copyWith(streamline: (n % 5) / 4),
          pressure: (i) => random.nextDouble(),
        );
        final keys = StrokeChunks.of(stroke);
        expect(keys.containsAll(_renderedChunks(stroke)), isTrue, reason: 'stroke $n');
        expect(
          keys.every(ChunkGrid.rangeFor(stroke.bounds).contains),
          isTrue,
          reason: 'never beyond the bounding box',
        );
      }
    });
  });

  test('storage and memory index the same chunks', () {
    final db = AppDatabase.inMemory();
    final repo = StrokeRepository(db, deviceId: 'd');
    final line = _stroke('d', [const Offset(0, 0), const Offset(3000, 2000)]);
    repo.save([line]);
    final rows = db.db.select('SELECT cx, cy FROM stroke_chunks WHERE stroke_id = ?', ['d']);
    final stored = {for (final r in rows) (x: r['cx'] as int, y: r['cy'] as int)};
    expect(stored, StrokeChunks.of(line));

    final model = SurfaceModel(surfaceId: 's', repository: repo)
      ..ensureLoaded(const Rect.fromLTWH(-100, -100, 4000, 3000));
    final everything = ChunkGrid.rangeFor(const Rect.fromLTWH(-100, -100, 4000, 3000));
    expect(model.chunksIn(everything).toSet(), stored);

    // A chunk inside the bounding box but off the path stays unpopulated.
    expect(repo.populatedChunks('s', const ChunkRange(5, 0, 5, 0)), isEmpty);
    model.dispose();
    db.close();
  });

  test('SpatialIndex insertAt / removeAt', () {
    final index = SpatialIndex()
      ..insertAt('a', [(x: 0, y: 0), (x: 3, y: 3)])
      ..insertAt('b', [(x: 3, y: 3)]);
    expect(index.chunkCount, 2);
    expect(index.query(const Rect.fromLTWH(1600, 1600, 1, 1)), {'a', 'b'});
    index.removeAt('a', [(x: 0, y: 0), (x: 3, y: 3)]);
    expect(index.chunkCount, 1);
    expect(index.idsIn((x: 3, y: 3)), {'b'});
  });
}
