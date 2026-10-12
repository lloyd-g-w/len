import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/sliced_stroke_reader.dart';
import 'package:len/data/stroke_reader.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/stroke.dart';

Stroke _stroke(String id, Offset from, Offset to) => Stroke(
  id: id,
  surfaceId: 's',
  tool: InkTool.pen,
  color: 0xFF000000,
  width: 2,
  points: [StrokePoint(from.dx, from.dy, 0.5), StrokePoint(to.dx, to.dy, 0.5)],
  createdAt: 1,
);

Set<String> _ids(ChunkLoad load) => {for (final s in load.strokes) s.id};

void main() {
  late AppDatabase db;
  late StrokeRepository repo;

  setUp(() {
    db = AppDatabase.inMemory();
    repo = StrokeRepository(db, deviceId: 'd');
    // A 10 × 10 grid of short strokes, one per chunk, and one long stroke
    // across the first row (it reaches every slice of that row).
    repo.save([
      for (var y = 0; y < 10; y++)
        for (var x = 0; x < 10; x++)
          _stroke(
            's$x-$y',
            Offset(x * 512.0 + 100, y * 512.0 + 100),
            Offset(x * 512.0 + 120, y * 512.0 + 100),
          ),
      _stroke('long', const Offset(10, 300), const Offset(5000, 300)),
    ]);
  });
  tearDown(() => db.close());

  const everything = ChunkRange(0, 0, 9, 9);

  test('small reads stay synchronous', () {
    final reader = SlicedStrokeReader(repo.queries, sliceChunks: 32);
    final result = reader.read('s', const ChunkRange(0, 0, 2, 2));
    expect(result, isA<ChunkLoad>());
    expect(_ids(result as ChunkLoad), _ids(repo.read('s', const ChunkRange(0, 0, 2, 2))));
  });

  test('large reads yield between slices and return the same content', () async {
    var yields = 0;
    final reader = SlicedStrokeReader(
      repo.queries,
      sliceChunks: 8,
      budget: Duration.zero,
      yieldToFrame: () async => yields++,
    );
    final result = reader.read('s', everything);
    expect(result, isA<Future<ChunkLoad>>());
    final load = await result;
    final expected = repo.read('s', everything);
    expect(_ids(load), _ids(expected));
    expect(load.strokes, hasLength(101)); // "long" once
    expect(load.chunks.toSet(), expected.chunks.toSet());
    expect(yields, 12); // 100 chunks in 13 slices, no yield after the last
  });

  test('skipped chunks are not read', () async {
    final reader = SlicedStrokeReader(repo.queries, sliceChunks: 8, budget: Duration.zero);
    final skip = {for (var x = 0; x < 10; x++) (x: x, y: 0)};
    final load = await reader.read('s', everything, skip: skip);
    expect(load.chunks, hasLength(90));
    expect(_ids(load), isNot(contains('long')));
    expect(_ids(load), isNot(contains('s0-0')));
  });
}
