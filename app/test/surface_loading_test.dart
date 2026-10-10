import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/background_stroke_reader.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_reader.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/undo_history.dart';

import 'elements_test.dart' show textBox;

Stroke _stroke(String id, Offset at) => Stroke(
  id: id,
  surfaceId: 's',
  tool: InkTool.pen,
  color: 0xFF000000,
  width: 2,
  points: [StrokePoint(at.dx, at.dy, 0.5), StrokePoint(at.dx + 10, at.dy, 0.5)],
  createdAt: 1,
);

/// Answers reads only when the test says so, recording what was asked.
class _ManualReader implements StrokeReader {
  _ManualReader(this.inner);

  final StrokeReader inner;
  final List<({ChunkRange range, Set<ChunkKey> skip, Completer<ChunkLoad> done})> calls = [];

  @override
  Future<ChunkLoad> read(String surfaceId, ChunkRange range, {Set<ChunkKey> skip = const {}}) {
    final done = Completer<ChunkLoad>();
    calls.add((range: range, skip: skip, done: done));
    return done.future;
  }

  /// Answers call [i] with what storage holds *now*.
  Future<void> answer(int i) async {
    final call = calls[i];
    call.done.complete(await inner.read('s', call.range, skip: call.skip));
    await Future<void>.delayed(Duration.zero);
  }

  @override
  FutureOr<Map<ChunkKey, int>> chunkDensity(String surfaceId) => inner.chunkDensity(surfaceId);

  @override
  FutureOr<Rect?> contentBounds(String surfaceId) => inner.contentBounds(surfaceId);
}

void main() {
  late AppDatabase db;
  late StrokeRepository repo;

  setUp(() {
    db = AppDatabase.inMemory();
    repo = StrokeRepository(db, deviceId: 'd');
  });
  tearDown(() => db.close());

  group('asynchronous loading', () {
    test('results arrive later; only the newest queued range is read next', () async {
      repo.save([for (var i = 0; i < 5; i++) _stroke('s$i', Offset(i * 5000.0, 0))]);
      final reader = _ManualReader(repo);
      final model = SurfaceModel(surfaceId: 's', repository: repo, reader: reader);

      model.ensureLoaded(const Rect.fromLTWH(0, 0, 100, 100));
      expect(model.isLoading, isTrue);
      expect(model.strokeById('s0'), isNull);
      // Panning on while the read runs: intermediate ranges are skipped.
      model
        ..ensureLoaded(const Rect.fromLTWH(5000, 0, 100, 100))
        ..ensureLoaded(const Rect.fromLTWH(10000, 0, 100, 100));
      expect(reader.calls, hasLength(1));

      await reader.answer(0);
      expect(model.strokeById('s0'), isNotNull);
      expect(reader.calls, hasLength(2));
      expect(
        reader.calls[1].range,
        ChunkGrid.rangeFor(const Rect.fromLTWH(9488, -512, 1124, 1124)),
      );

      await reader.answer(1);
      expect(model.strokeById('s2'), isNotNull);
      expect(model.strokeById('s1'), isNull);
      expect(model.isLoading, isFalse);
      await model.loaded;
      model.dispose();
    });

    test('already loaded chunks are not read again', () async {
      repo.save([_stroke('a', const Offset(10, 10))]);
      final reader = _ManualReader(repo);
      final model = SurfaceModel(surfaceId: 's', repository: repo, reader: reader)
        ..ensureLoaded(const Rect.fromLTWH(0, 0, 100, 100));
      await reader.answer(0);
      model.ensureLoaded(const Rect.fromLTWH(600, 0, 100, 100));
      expect(reader.calls[1].skip, contains((x: 0, y: 0)));
      model.dispose();
    });

    test('a stroke erased while a read is in flight is not resurrected', () async {
      repo.save([_stroke('a', const Offset(10, 10))]);
      final reader = _ManualReader(repo);
      final model = SurfaceModel(surfaceId: 's', repository: repo);
      model.ensureLoaded(const Rect.fromLTWH(0, 0, 100, 100)); // sync: 'a' loaded

      // A second model on the same surface reads asynchronously.
      final lagging = SurfaceModel(surfaceId: 's', repository: repo, reader: reader)
        ..ensureLoaded(const Rect.fromLTWH(0, 0, 100, 100));
      final stale = repo.read('s', reader.calls.single.range);
      lagging.addStroke(_stroke('b', const Offset(20, 40)));
      expect(
        lagging.eraseAlong(const Offset(25, 30), const Offset(25, 50), 4, continueEdit: false),
        isTrue,
      );
      reader.calls.single.done.complete(
        ChunkLoad(
          chunks: stale.chunks,
          strokes: [...stale.strokes, _stroke('b', const Offset(20, 40))],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(lagging.strokeById('a'), isNotNull);
      expect(lagging.strokeById('b'), isNull);
      model.dispose();
      lagging.dispose();
    });

    test('reload drops a read in flight', () async {
      repo.save([_stroke('a', const Offset(10, 10))]);
      final reader = _ManualReader(repo);
      final model = SurfaceModel(surfaceId: 's', repository: repo, reader: reader)
        ..ensureLoaded(const Rect.fromLTWH(0, 0, 100, 100));
      model.reload();
      expect(reader.calls, hasLength(2));
      reader.calls.first.done.complete(
        ChunkLoad(chunks: const [(x: 0, y: 0)], strokes: [_stroke('ghost', const Offset(1, 1))]),
      );
      await reader.answer(1);
      expect(model.strokeById('ghost'), isNull);
      expect(model.strokeById('a'), isNotNull);
      model.dispose();
    });

    test('elements load through the reader; one moved during a read keeps its new place', () async {
      final elements = ElementRepository(db, deviceId: 'd');
      elements.save([textBox('t', const Offset(10, 10)), textBox('far', const Offset(9e5, 0))]);
      repo.save([_stroke('a', const Offset(10, 60))]);
      final reader = _ManualReader(repo);
      final model = SurfaceModel(
        surfaceId: 's',
        repository: repo,
        elementRepository: elements,
        reader: reader,
      )..ensureLoaded(const Rect.fromLTWH(0, 0, 100, 100));
      // A read that predates the move (answered with the old storage state).
      final stale = repo.read('s', reader.calls.single.range);
      expect(stale.elements.map((e) => e.id), ['t']);
      final original = stale.elements.single;
      final moved = original.copyWith(rect: original.rect.shift(const Offset(40, 0)));
      model.commit(InkEdit(removedElements: [original], addedElements: [moved]));
      model.setHidden({'t'}); // e.g. still selected
      reader.calls.single.done.complete(stale);
      await Future<void>.delayed(Duration.zero);
      expect(model.strokeById('a'), isNotNull);
      expect(model.elementById('t')?.rect, moved.rect);
      expect(model.elementById('far'), isNull);
      expect(model.isHidden('t'), isTrue);
      model.dispose();
    });

    test('lazy loading and eviction still hold with async reads', () async {
      repo.save([for (var i = 0; i < 20; i++) _stroke('s$i', Offset(i * 5000.0, 0))]);
      final reader = _ManualReader(repo);
      final model = SurfaceModel(
        surfaceId: 's',
        repository: repo,
        reader: reader,
        maxLoadedChunks: 4,
      );
      for (var i = 0; i < 10; i++) {
        model.ensureLoaded(Rect.fromLTWH(i * 5000.0, 0, 100, 100));
        await reader.answer(i);
      }
      expect(model.strokeById('s9'), isNotNull);
      expect(model.strokeById('s0'), isNull);
      expect(model.loadedStrokeCount, lessThan(10));
      model.dispose();
    });
  });

  test('BackgroundStrokeReader reads in a worker isolate, concurrently with writes', () async {
    final dir = Directory.systemTemp.createTempSync('len_reader_');
    final file = AppDatabase.open('${dir.path}/len.db');
    final strokes = StrokeRepository(file, deviceId: 'd');
    strokes.save([for (var i = 0; i < 30; i++) _stroke('s$i', Offset(i * 100.0, i * 700.0))]);
    final reader = BackgroundStrokeReader(file.path!, fallback: strokes);
    try {
      final range = ChunkGrid.rangeFor(const Rect.fromLTWH(0, 0, 3000, 21000));
      final load = await reader.read('s', range);
      final expected = strokes.read('s', range);
      expect(load.chunks.toSet(), expected.chunks.toSet());
      expect(load.strokes.map((s) => s.id).toSet(), {for (var i = 0; i < 30; i++) 's$i'});

      // A write committed on the UI connection is visible to the next read.
      strokes.save([_stroke('late', const Offset(10, 10))]);
      final again = await reader.read('s', range, skip: {(x: 0, y: 1)});
      expect(again.strokes.map((s) => s.id), contains('late'));
      expect(again.chunks, isNot(contains((x: 0, y: 1))));

      expect(await reader.chunkDensity('s'), strokes.chunkDensity('s'));
      expect(await reader.contentBounds('s'), strokes.contentBounds('s'));

      // Elements come along in the same read (and count towards overviews).
      final elements = ElementRepository(file, deviceId: 'd');
      elements.save([textBox('t', const Offset(-900, 30))]);
      final withText = await reader.read(
        's',
        ChunkGrid.rangeFor(const Rect.fromLTWH(-900, 0, 10, 10)),
      );
      expect(withText.elements.map((e) => e.id), ['t']);
      expect(withText.elements.single.data, textBox('t', Offset.zero).data);
      expect(await reader.chunkDensity('s'), strokes.chunkDensity('s'));
      expect((await reader.contentBounds('s'))!.left, -900);

      // Drives a SurfaceModel end to end.
      final model = SurfaceModel(
        surfaceId: 's',
        repository: strokes,
        elementRepository: elements,
        reader: reader,
      )..ensureLoaded(const Rect.fromLTWH(-500, 0, 500, 500));
      expect(model.isLoading, isTrue);
      await model.loaded;
      expect(model.strokeById('late'), isNotNull);
      expect(model.elementById('t'), isNotNull);
      model.dispose();
    } finally {
      reader.close();
      file.close();
      dir.deleteSync(recursive: true);
    }
  });

  test('contentBounds is exact and density counts strokes per chunk', () {
    repo.save([
      _stroke('a', const Offset(100, 100)),
      _stroke('b', const Offset(130, 100)),
      _stroke('c', const Offset(-2000, 900)),
    ]);
    expect(repo.contentBounds('s'), const Rect.fromLTRB(-2002, 98, 142, 902));
    expect(repo.chunkDensity('s'), {(x: 0, y: 0): 2, (x: -4, y: 1): 1});
    expect(repo.contentBounds('empty'), isNull);

    // Elements count too.
    ElementRepository(db, deviceId: 'd').save([textBox('t', const Offset(200, 900))]);
    expect(repo.contentBounds('s'), const Rect.fromLTRB(-2002, 98, 320, 930));
    expect(repo.chunkDensity('s'), {(x: 0, y: 0): 2, (x: -4, y: 1): 1, (x: 0, y: 1): 1});
  });
}
