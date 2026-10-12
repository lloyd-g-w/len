import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/render/background_outlines.dart';
import 'package:len/ink/render/outline_preparer.dart';
import 'package:len/ink/render/stroke_renderer.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/undo_history.dart';

import 'support/canvas_fixtures.dart';

/// Reports the first [early] strokes of each batch at once, the rest only
/// when told to.
class _SlicedPreparer implements OutlinePreparer {
  _SlicedPreparer(this.early);

  final int early;
  final List<void Function()> pending = [];
  final List<List<Stroke>> batches = [];

  @override
  Future<void> prepare(List<Stroke> strokes, {void Function(List<Stroke> ready)? onReady}) {
    batches.add(strokes);
    final first = strokes.take(early).toList();
    for (final s in first) {
      StrokeRenderer.pathOf(s);
    }
    onReady?.call(first);
    final c = Completer<void>();
    pending.add(() {
      final rest = strokes.skip(early).toList();
      for (final s in rest) {
        StrokeRenderer.pathOf(s);
      }
      onReady?.call(rest);
      c.complete();
    });
    return c.future;
  }

  void release() {
    for (final p in pending) {
      p();
    }
    pending.clear();
  }

  @override
  void close() {}
}

/// Completes preparations only when told to.
class _GatedPreparer implements OutlinePreparer {
  final List<Completer<void>> pending = [];

  @override
  Future<void> prepare(List<Stroke> strokes, {void Function(List<Stroke> ready)? onReady}) {
    final c = Completer<void>();
    pending.add(c);
    return c.future;
  }

  void release() {
    for (final c in pending) {
      c.complete();
    }
    pending.clear();
  }

  @override
  void close() {}
}

void main() {
  test('worker outlines equal the ones built in place', () async {
    final strokes = scribbles(120, const Rect.fromLTWH(0, 0, 800, 600), seed: 9, points: 40);
    final copies = [for (final s in strokes) s.withPoints(s.points)];
    final workers = BackgroundOutlines(workers: 2, buildHere: false);
    await workers.prepare(strokes);
    workers.close();
    for (var i = 0; i < strokes.length; i++) {
      expect(StrokeRenderer.hasPath(strokes[i]), isTrue);
      final a = StrokeRenderer.pathOf(strokes[i]).getBounds();
      final b = StrokeRenderer.pathOf(copies[i]).getBounds();
      expect((a.left - b.left).abs() + (a.right - b.right).abs(), lessThan(1e-3));
      expect((a.top - b.top).abs() + (a.bottom - b.bottom).abs(), lessThan(1e-3));
      final metricsA = StrokeRenderer.pathOf(strokes[i]).computeMetrics().toList();
      final metricsB = StrokeRenderer.pathOf(copies[i]).computeMetrics().toList();
      expect(metricsA.length, metricsB.length);
      for (var k = 0; k < metricsA.length; k++) {
        expect(metricsA[k].length, closeTo(metricsB[k].length, 1e-3));
      }
    }
  });

  test('loads wait for their outlines; edits made meanwhile win', () async {
    final strokes = scribbles(40, const Rect.fromLTWH(0, 0, 400, 400), seed: 3);
    final gate = _GatedPreparer();
    final db = AppDatabase.inMemory();
    final model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
      reader: MemoryStrokeReader(strokes),
      outlines: gate,
    );
    model.ensureLoaded(const Rect.fromLTWH(0, 0, 400, 400));
    expect(model.loadedStrokeCount, 0);
    expect(model.isLoading, isTrue);
    // A stroke drawn meanwhile, then erased again.
    final mine = strokes.first.withPoints(strokes.first.points, id: 'mine');
    model.addStroke(mine);
    model.commit(InkEdit(removed: [strokes[1]]));
    gate.release();
    await model.loaded;
    expect(model.isLoading, isFalse);
    expect(model.strokeById('mine'), isNotNull);
    expect(model.strokeById(strokes[1].id), isNull, reason: 'erased while loading');
    expect(model.loadedStrokeCount, strokes.length);
    model.dispose();
    db.close();
  });

  test('outlines arrive slice by slice, each stroke once, in order', () async {
    final strokes = scribbles(100, const Rect.fromLTWH(0, 0, 800, 600), seed: 4, points: 30);
    // Workers and the UI isolate share the work.
    final workers = BackgroundOutlines(workers: 2, sliceSize: 16);
    final slices = <List<Stroke>>[];
    await workers.prepare(
      strokes,
      onReady: (ready) {
        expect(ready.every(StrokeRenderer.hasPath), isTrue);
        slices.add(ready);
      },
    );
    workers.close();
    expect(slices.length, greaterThan(1));
    expect(slices.every((s) => s.length <= 16), isTrue);
    final seen = [for (final s in slices) ...s];
    expect(seen.toSet(), strokes.toSet());
    expect(seen.length, strokes.length);
    // Two loops per worker: slices finish in roughly the order given.
    expect(strokes.indexOf(slices.first.first), lessThan(16 * 4));
  });

  test('loads show their first strokes before the rest is ready, nearest first', () async {
    // Two clusters in one load: one in the middle of the view, one in the
    // next chunk diagonally (loaded with the view's surroundings).
    final far = [
      for (final s in scribbles(30, const Rect.fromLTWH(800, 800, 150, 150), seed: 5))
        s.withPoints(s.points, id: 'far-${s.id}'),
    ];
    final near = scribbles(30, const Rect.fromLTWH(20, 20, 200, 200), seed: 6);
    final prep = _SlicedPreparer(30);
    final db = AppDatabase.inMemory();
    final model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
      reader: MemoryStrokeReader([...far, ...near]),
      outlines: prep,
    );
    var notified = 0;
    model.addListener(() => notified++);
    model.ensureLoaded(const Rect.fromLTWH(-200, -200, 600, 600));
    final all = prep.batches.single.toSet();
    expect(all, {...far, ...near});
    // The near cluster came first and is in the model already.
    expect(prep.batches.single.take(30).toSet(), near.toSet());
    expect(model.loadedStrokeCount, near.length);
    expect(notified, greaterThan(0));
    expect(model.isLoading, isTrue);
    // Erasing a stroke shown early keeps it erased when the load completes.
    model.commit(InkEdit(removed: [near.first]));
    prep.release();
    await model.loaded;
    expect(model.isLoading, isFalse);
    expect(model.strokeById(near.first.id), isNull);
    expect(model.loadedStrokeCount, all.length - 1);
    model.dispose();
    db.close();
  });
}
