import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_reader.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/chunk_digest.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/canvas/minimap_raster.dart';
import 'package:len/features/editor/canvas/minimap_sketch.dart';

Stroke _line(String id, Offset at, {int points = 40}) => Stroke(
  id: id,
  surfaceId: 's',
  tool: InkTool.ballpoint,
  color: 0xFF1F2937,
  width: 4,
  points: [for (var i = 0; i < points; i++) StrokePoint(at.dx + i * 0.5, at.dy, 0.5)],
  createdAt: 1,
);

/// Records which chunks are read.
class _Reader implements StrokeReader {
  _Reader(this._inner);

  final StrokeRepository _inner;
  final List<Set<ChunkKey>> reads = [];

  @override
  FutureOr<ChunkLoad> read(String surfaceId, ChunkRange range, {Set<ChunkKey> skip = const {}}) {
    final load = _inner.read(surfaceId, range, skip: skip);
    reads.add(load.chunks.toSet());
    return load;
  }

  @override
  FutureOr<Map<ChunkKey, ChunkDigest>> chunkDigests(String surfaceId, ChunkRange range) =>
      _inner.chunkDigests(surfaceId, range);

  @override
  FutureOr<Map<ChunkKey, int>> chunkDensity(String surfaceId) => _inner.chunkDensity(surfaceId);

  @override
  FutureOr<Rect?> contentBounds(String surfaceId) => _inner.contentBounds(surfaceId);
}

void main() {
  late StrokeRepository repo;
  late _Reader reader;

  setUp(() {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    repo = StrokeRepository(db, deviceId: 'd');
    reader = _Reader(repo);
  });

  int strokesIn(MinimapSketch sketch) =>
      sketch.tiles.fold(0, (n, t) => n + sketch.itemsOf(t).strokes.length);

  test('reads everything once, then only the chunks that changed', () async {
    repo.save([_line('a', const Offset(100, 100)), _line('b', const Offset(5000, 3000))]);
    final sketch = MinimapSketch();
    expect(await sketch.update(reader, 's'), isTrue);
    expect(strokesIn(sketch), 2);
    expect(sketch.sketched, isTrue);
    expect(sketch.bounds!.contains(const Offset(110, 100)), isTrue);
    expect(sketch.bounds!.width, lessThan(5000), reason: 'the exact bounds, not chunks');
    expect(sketch.takeDirty(), hasLength(2));

    reader.reads.clear();
    expect(await sketch.update(reader, 's'), isFalse, reason: 'nothing changed');
    expect(reader.reads, isEmpty);

    repo.save([_line('c', const Offset(5050, 3050))]);
    expect(await sketch.update(reader, 's'), isTrue);
    expect(reader.reads.expand((r) => r).toSet(), {ChunkGrid.keyAt(5000, 3000)});
    expect(strokesIn(sketch), 3);
    expect(sketch.takeDirty(), hasLength(1));

    repo.delete(['a']);
    expect(await sketch.update(reader, 's'), isTrue);
    expect(strokesIn(sketch), 2);
    expect(sketch.bounds!.left, greaterThan(4000));
  });

  test('a canvas over the budget keeps only blocks, and sketches again below it', () async {
    repo.save([for (var i = 0; i < 4; i++) _line('s$i', Offset(i * 600.0 + 100, 100))]);
    final sketch = MinimapSketch(maxItems: 3);
    await sketch.update(reader, 's');
    expect(sketch.overBudget, isTrue);
    expect(sketch.tiles, isEmpty);
    expect(sketch.blocks.cells, isNotEmpty);
    repo.delete(['s3']);
    await sketch.update(reader, 's');
    expect(sketch.overBudget, isFalse);
    expect(strokesIn(sketch), 3);
  });

  test('strokes keep fewer points, their ends and bounds', () {
    final s = _line('a', Offset.zero, points: 100);
    final simple = MinimapSketch.simplify(s, 5);
    expect(simple.points.length, lessThan(15));
    expect(simple.points.first.offset, s.points.first.offset);
    expect(simple.points.last.offset, s.points.last.offset);
    expect(simple.bounds, s.bounds);
  });

  testWidgets('the miniature draws the ink in its colour', (tester) async {
    repo.save([
      Stroke(
        id: 'red',
        surfaceId: 's',
        tool: InkTool.ballpoint,
        color: 0xFFE03131,
        width: 40,
        points: [for (var i = 0; i < 20; i++) StrokePoint(i * 50.0, 0, 0.5)],
        createdAt: 1,
      ),
    ]);
    final sketch = MinimapSketch();
    await sketch.update(reader, 's');
    final raster = MinimapRaster();
    addTearDown(raster.dispose);
    raster.sync(sketch);
    await raster.render(sketch, const Rect.fromLTWH(-100, -300, 1200, 600), const Size(120, 60));
    final image = raster.overview!;
    final bytes = (await tester.runAsync(image.image.toByteData))!;
    // The middle of the line, at (500, 0) in the world: (60, 30) on the image.
    final i = (30 * 120 + 60) * 4;
    expect(bytes.getUint8(i), greaterThan(180)); // red
    expect(bytes.getUint8(i + 1), lessThan(120));
    expect(bytes.getUint8(i + 3), greaterThan(200)); // opaque
    // Far from it: nothing.
    expect(bytes.getUint8((5 * 120 + 5) * 4 + 3), 0);
  });
}
