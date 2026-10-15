import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/document/page_thumbnail_cache.dart';

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
