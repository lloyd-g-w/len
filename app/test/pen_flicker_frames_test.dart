// The pen never flickers: rendered frame by frame, no frame loses ink the
// frame before it showed (a pixel inked in frame N but not in N + 1),
// while a stroke is written, at its pen-up and while the ink re-renders —
// whatever the tile caches are doing meanwhile (renders pending, a zoom
// being adopted, a text box above the ink, zoomed far out).
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/ink/undo_history.dart';

import 'support/canvas_fixtures.dart';
import 'support/ink_frames.dart';
import 'support/ink_scene.dart';

/// A long wavy stroke (world units), crossing many tiles.
List<StrokePoint> wave({double x = 30, double y = 120, double length = 528}) => [
  for (var i = 0; i <= 240; i++)
    StrokePoint(x + i * length / 240, y + 90 * (i / 240) + 18 * ((i % 40) / 40 - 0.5).abs(), 0.55),
];

/// Pen ink already on the canvas.
List<Stroke> background() => [
  for (final s in scribbles(300, const Rect.fromLTWH(0, 0, 600, 400), seed: 4))
    if (!s.tool.isHighlighter) s,
];

/// A text box (drawn above the ink) at [rect].
SurfaceElement textBox(Rect rect) => SurfaceElement(
  id: 'box',
  surfaceId: 's',
  type: ElementType.text.name,
  rect: rect,
  z: 1,
  createdAt: 1,
  data: TextData.rich(text: 'note').toJson(),
);

InkFrames framesOf(InkScene scene) => InkFrames(
  size: scene.size,
  dpr: scene.dpr,
  viewport: scene.viewport,
  paintInk: (canvas) => scene.painter().paint(canvas, scene.size),
);

/// Whether [scene]'s ink is drawn from its own, current images.
bool settledTiles(InkScene scene) {
  final paint = scene.tiles.lastPaint;
  return !scene.busy &&
      paint.staleImages == 0 &&
      paint.overlayStrokes == 0 &&
      paint.underlayStrokes == 0 &&
      paint.vectorTiles == 0;
}

/// The end of the stroke may change at pen-up (the settled end, its
/// taper): pixels near [stroke]'s last point are not judged there.
List<Rect> endOf(InkFrames frames, List<StrokePoint> stroke) => [
  frames.around(stroke.last.offset, 8),
];

void main() {
  testWidgets('pen-up over a text box\'s chunk: the stroke never vanishes (many tiles)', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // A text box above the ink in the stroke's chunk: no append.
      final scene = InkScene(background(), dpr: 2);
      scene.model.commit(InkEdit(addedElements: [textBox(const Rect.fromLTWH(420, 300, 120, 40))]));
      await scene.warm();
      final f = framesOf(scene);
      final points = wave();
      final live = await f.draw(points);
      f.lift(scene.model);
      final after = [live.last, await f.frame(), ...await f.until(() => settledTiles(scene))];
      await expectNoLostInk(after, except: endOf(f, points), what: 'frame after pen-up');
      scene.dispose();
    });
  });

  testWidgets('pen-up while a zoom\'s new tiles are still rendering: nothing vanishes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final batch = HeldBatch();
      final scene = InkScene(background(), dpr: 2, batch: batch);
      await scene.warm();
      final f = framesOf(scene);
      // Zoom in a little and let the new zoom be adopted, its tiles held
      // back (a busy raster thread): the old ones stand in, scaled.
      scene.viewport.zoomAt(const Offset(300, 200), 1.3);
      await f.frame();
      batch.hold = true;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final points = wave(x: 120, y: 140, length: 300);
      final frames = [await f.frame(), ...await f.draw(points)];
      expect(batch.waiting, greaterThan(0), reason: 'tiles still rendering');
      f.lift(scene.model);
      frames.add(await f.frame());
      frames.add(await f.frame());
      batch.release();
      frames.addAll(await f.until(() => settledTiles(scene)));
      await expectNoLostInk(frames, except: endOf(f, points));
      scene.dispose();
    });
  });

  testWidgets('zooming right after a stroke, before its tiles took it: nothing vanishes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final batch = HeldBatch();
      final scene = InkScene(background(), dpr: 2, batch: batch);
      await scene.warm();
      final f = framesOf(scene);
      final points = wave(x: 120, y: 140, length: 300);
      final frames = await f.draw(points);
      batch.hold = true; // The stroke's tiles wait (or, on the web, the pen rests).
      f.lift(scene.model);
      frames.add(await f.frame());
      await expectNoLostInk(frames, except: endOf(f, points));
      scene.viewport.zoomAt(const Offset(300, 200), 1.3);
      final zoomed = [await f.frame()];
      // The new zoom is adopted; its tiles are held back too.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      zoomed
        ..add(await f.frame())
        ..add(await f.frame());
      batch.release();
      zoomed.addAll(await f.until(() => settledTiles(scene)));
      await expectNoLostInk(zoomed, what: 'zoomed frame');
      scene.dispose();
    });
  });

  testWidgets('zoomed far out (level-of-detail rasters), over a text box\'s chunk: steady pen-up', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // Bold ink, so it shows at 10 %.
      final ink = [
        for (final s in scribbles(400, const Rect.fromLTWH(0, 0, 6000, 4000), seed: 2))
          if (!s.tool.isHighlighter)
            Stroke(
              id: s.id,
              surfaceId: s.surfaceId,
              tool: s.tool,
              color: s.color,
              width: 24,
              points: [for (final p in s.points) StrokePoint(p.x, p.y, p.pressure)],
              createdAt: s.createdAt,
              style: s.style,
            ),
      ];
      final scene = InkScene(ink, scale: 0.1, lod: true);
      scene.model.commit(
        InkEdit(addedElements: [textBox(const Rect.fromLTWH(600, 1300, 300, 100))]),
      );
      await scene.warm();
      final f = framesOf(scene);
      // Across a dozen chunks: more than a frame may record as vectors.
      final points = wave(x: 300, y: 1500, length: 5200);
      final live = await f.draw(points, width: 30);
      f.lift(scene.model);
      final after = [live.last, await f.frame(), ...await f.until(() => !scene.busy)];
      await expectNoLostInk(after, except: endOf(f, points), what: 'frame after pen-up');
      scene.dispose();
    });
  });
}
