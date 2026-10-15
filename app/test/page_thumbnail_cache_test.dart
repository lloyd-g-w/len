import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/document/page_thumbnail_cache.dart';
import 'package:len/ink/render/raster_batch.dart';

import 'support/canvas_fixtures.dart';

void main() {
  testWidgets('thumbnails are drawn from rasters at the size shown, the old one standing in', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final db = AppDatabase.inMemory();
      final strokes = StrokeRepository(db, deviceId: 'd');
      const page = Size(794, 1123);
      strokes.save([
        for (final s in scribbles(300, const Rect.fromLTWH(40, 40, 700, 1000)))
          Stroke(
            id: s.id,
            surfaceId: 'p',
            tool: s.tool,
            color: s.color,
            width: s.width,
            points: s.points,
            createdAt: s.createdAt,
            style: s.style,
          ),
      ]);
      final cache = ThumbnailCache(SurfaceCopier(strokes));
      var notified = 0;
      cache.addListener(() => notified++);
      expect(cache.inkOf('p'), isNull); // Recorded between frames.
      await settle(() => cache.inkOf('p') != null);
      expect(cache.rasterOf('p', page, 300, 424), isNull, reason: 'the picture stands in');
      await settle(() => cache.rasterOf('p', page, 300, 424) != null);
      final first = cache.rasterOf('p', page, 300, 424)!;
      expect((first.width, first.height), (300, 424));
      // The page changed: the old raster shows until the new one is ready.
      cache.invalidate('p');
      final before = notified;
      await settle(() => notified > before);
      expect(cache.rasterOf('p', page, 300, 424), same(first));
      await settle(() => !identical(cache.rasterOf('p', page, 300, 424), first));
      expect(cache.rasterOf('p', page, 300, 424), isNotNull);
      cache.dispose();
      db.close();
    });
  });

  testWidgets('batched (the JavaScript build), the thumbnails on screen share read-backs', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final db = AppDatabase.inMemory();
      final strokes = StrokeRepository(db, deviceId: 'd');
      const page = Size(794, 1123);
      for (var p = 0; p < 6; p++) {
        strokes.save([
          for (final s in scribbles(20, const Rect.fromLTWH(40, 40, 700, 1000), seed: p))
            Stroke(
              id: 'p$p-${s.id}',
              surfaceId: 'p$p',
              tool: s.tool,
              color: s.color,
              width: s.width,
              points: s.points,
              createdAt: s.createdAt,
              style: s.style,
            ),
        ]);
      }
      final batch = RasterBatch(batching: true);
      final cache = ThumbnailCache(SurfaceCopier(strokes), batch: batch);
      final ids = [for (var p = 0; p < 6; p++) 'p$p'];
      for (final id in ids) {
        cache.inkOf(id);
      }
      await settle(() => ids.every((id) => cache.inkOf(id) != null));
      // A frame of thumbnails 68 × 96 asks for every raster.
      bool all() =>
          [for (final id in ids) cache.rasterOf(id, page, 68, 96)].every((r) => r != null);
      all();
      await settle(all);
      expect(batch.readbacks, 1);
      final rasters = [for (final id in ids) cache.rasterOf(id, page, 68, 96)!];
      expect(rasters.map((r) => (r.width, r.height)).toSet(), {(68, 96)});
      expect(rasters.map((r) => r.source).toSet(), hasLength(6));
      cache.dispose();
      db.close();
    });
  });

  test('nothing is recorded while deferred; what waits on screen is, once it stops', () {
    fakeAsync((async) {
      final db = AppDatabase.inMemory();
      final strokes = StrokeRepository(db, deviceId: 'd');
      final defer = ValueNotifier(true);
      final cache = ThumbnailCache(SurfaceCopier(strokes), defer: defer);
      for (final id in ['a', 'b', 'c']) {
        cache.shown(id);
        expect(cache.inkOf(id), isNull);
      }
      async.elapse(const Duration(milliseconds: 50));
      expect(cache.recordings, 0);
      cache.hidden('a'); // Scrolled past while fast: never recorded.
      defer.value = false;
      async.elapse(Duration.zero);
      expect(cache.recordings, 2);
      expect(
        [cache.isRecorded('a'), cache.isRecorded('b'), cache.isRecorded('c')],
        [false, true, true],
      );
      cache.dispose();
      defer.dispose();
      db.close();
    });
  });
}
