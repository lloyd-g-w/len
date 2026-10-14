import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/render/sliced_outline_preparer.dart';
import 'package:len/ink/render/stroke_renderer.dart';
import 'package:len/ink/surface_model.dart';

import 'support/canvas_fixtures.dart';

/// The web builds outlines on the UI thread: a dense page arriving at once
/// (opening a 4,000-stroke notebook) froze the tab for over half a second
/// (tool/web_explore.py's long tasks). Now it yields between slices.
void main() {
  test('within the budget, outlines are built at once and the future is synchronous', () {
    final strokes = scribbles(5, const Rect.fromLTWH(0, 0, 400, 400), seed: 1);
    final ready = <Stroke>[];
    final done = SlicedOutlinePreparer(budget: const Duration(seconds: 10))
        .prepare(strokes, onReady: ready.addAll);
    expect(done, isA<SynchronousFuture<void>>());
    expect(ready, strokes);
    expect(strokes.every(StrokeRenderer.hasPath), isTrue);
  });

  test(
    'over the budget, slices yield in between; each stroke is reported once, in order',
    () async {
      final strokes = scribbles(40, const Rect.fromLTWH(0, 0, 800, 600), seed: 2, points: 30);
      var yields = 0;
      final slices = <List<Stroke>>[];
      // No budget: one stroke per slice.
      await SlicedOutlinePreparer(
        budget: Duration.zero,
        yieldToFrame: () async => yields++,
      ).prepare(
        strokes,
        onReady: (ready) {
          expect(ready.every(StrokeRenderer.hasPath), isTrue);
          slices.add(ready);
        },
      );
      expect(slices, hasLength(strokes.length));
      expect([for (final s in slices) ...s], strokes);
      expect(yields, strokes.length - 1);
    },
  );

  test('a surface fills in slice by slice and ends complete', () async {
    final strokes = scribbles(30, const Rect.fromLTWH(0, 0, 400, 400), seed: 3);
    final db = AppDatabase.inMemory();
    final model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
      reader: MemoryStrokeReader(strokes),
      outlines: SlicedOutlinePreparer(budget: Duration.zero),
    );
    model.ensureLoaded(const Rect.fromLTWH(0, 0, 400, 400));
    expect(model.isLoading, isTrue);
    expect(model.loadedStrokeCount, lessThan(strokes.length));
    await model.loaded;
    expect(model.isLoading, isFalse);
    expect(model.loadedStrokeCount, strokes.length);
    model.dispose();
    db.close();
  });
}
