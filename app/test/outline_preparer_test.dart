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

/// Completes preparations only when told to.
class _GatedPreparer implements OutlinePreparer {
  final List<Completer<void>> pending = [];

  @override
  Future<void> prepare(List<Stroke> strokes) {
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
    final workers = BackgroundOutlines(workers: 2);
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
}
