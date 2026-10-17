// The pen never flickers around zooms and pans either: rendered frame by
// frame, crossing between the level-of-detail rasters (zoomed far out) and
// the tiles never shows the ink missing for a frame, whatever is rendered
// yet; and after pans by fractions of a pixel the stroke stays exactly
// where it was drawn live at pen-up.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';

import 'pen_flicker_frames_test.dart' show background, endOf, framesOf, settledTiles, wave;
import 'support/canvas_fixtures.dart';
import 'support/ink_frames.dart';
import 'support/ink_scene.dart';

/// Bold ink over a large area, so it shows zoomed far out.
List<Stroke> boldInk() => [
  for (final s in scribbles(300, const Rect.fromLTWH(0, 0, 3000, 2000), seed: 3))
    if (!s.tool.isHighlighter)
      Stroke(
        id: s.id,
        surfaceId: s.surfaceId,
        tool: s.tool,
        color: s.color,
        width: 12,
        points: s.points,
        createdAt: s.createdAt,
        style: s.style,
      ),
];

/// Frames until [scene] has nothing left to render, the last one settled.
Future<List<Frame>> settling(InkScene scene, InkFrames f) async {
  final frames = <Frame>[];
  for (var i = 0; i < 120; i++) {
    frames.add(await f.frame());
    await Future<void>.delayed(const Duration(milliseconds: 4));
    if (!scene.busy && scene.tiles.lastPaint.blankPixels == 0) break;
  }
  frames.add(await f.frame());
  return frames;
}

/// Expects every frame of [frames] (one zoom) to show all the ink the
/// settled last one does: none blank, none lost.
Future<void> expectComplete(List<Frame> frames, String what) async {
  await expectNoLostInk(frames, what: what);
  final settled = frames.last;
  for (var k = 0; k < frames.length - 1; k++) {
    final missing = lostInk(settled, frames[k]);
    if (missing > 0) await expectNoLostInk([settled, frames[k]], what: '$what $k vs settled');
  }
}

void main() {
  for (final dpr in [1.0, 2.0]) {
    testWidgets('zooming in out of the level-of-detail rasters (${dpr}x): no ink missing', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final batch = HeldBatch();
        final scene = InkScene(boldInk(), scale: 1, dpr: dpr, lod: true, batch: batch);
        await scene.warm();
        final f = framesOf(scene);
        // Zoom out into level of detail (rasters of ≤ 256 px a chunk).
        scene.viewport.zoomAt(Offset.zero, 0.4 / dpr);
        scene.model.ensureLoaded(scene.viewport.visibleWorld);
        await settling(scene, f);
        // Back in, just past it: the tiles' new zoom is not rendered yet
        // (held a few frames, a busy raster thread).
        batch.hold = true;
        scene.viewport.zoomAt(Offset.zero, 1.5);
        final frames = [await f.frame(), await f.frame(), await f.frame()];
        expect(batch.waiting, greaterThan(0), reason: 'tiles still rendering');
        batch.release();
        frames.addAll(await settling(scene, f));
        await expectComplete(frames, 'zoomed-in frame');
        scene.dispose();
      });
    });

    testWidgets(
      'zooming out into the level-of-detail rasters after a highlight (${dpr}x): no ink missing',
      (tester) async {
        await tester.runAsync(() async {
          final batch = HeldBatch();
          final scene = InkScene(boldInk(), scale: 0.6 / dpr, dpr: dpr, lod: true, batch: batch);
          scene.model.ensureLoaded(scene.viewport.visibleWorld);
          await scene.warm();
          final f = framesOf(scene);
          // A highlight over many tiles just lifted: they keep their images,
          // stale, until rendered again — held (a busy raster thread).
          batch.hold = true;
          scene.model.addStroke(
            Stroke(
              id: 'highlight',
              surfaceId: 's',
              tool: InkTool.highlighter,
              color: 0x66FFEB3B,
              width: 40,
              points: [for (var x = 100.0; x < 1800; x += 20) StrokePoint(x, 600 + x / 4, .5)],
              createdAt: 1 << 41,
            ),
          );
          await f.frame();
          scene.viewport.zoomAt(Offset.zero, 0.8);
          final frames = [await f.frame(), await f.frame(), await f.frame()];
          batch.release();
          frames.addAll(await settling(scene, f));
          await expectComplete(frames, 'zoomed-out frame');
          scene.dispose();
        });
      },
    );
  }

  for (final dpr in [2.0, 2.625]) {
    testWidgets('pans by fractions of a pixel, then a stroke (${dpr}x): it stays put at pen-up', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final scene = InkScene(background(), dpr: dpr);
        scene.viewport.devicePixelRatio = dpr; // As the editors set it.
        await scene.warm();
        final f = framesOf(scene);
        // Pans, a zoom (the tiles' new pixels), pans again: none in whole
        // device pixels.
        for (final pan in const [Offset(13.37, -7.21), Offset(0.3, 0.45), Offset(-5.08, 2.9)]) {
          scene.viewport.panBy(pan);
          await f.frame();
        }
        scene.viewport.zoomAt(const Offset(201.3, 99.7), 1.1);
        await scene.warm();
        for (final pan in const [Offset(0.21, 0.33), Offset(7.77, -3.14), Offset(0.4, 0.1)]) {
          scene.viewport.panBy(pan);
          await f.frame();
        }
        await scene.warm();
        final points = wave(x: 120, y: 140, length: 300);
        // Stabiliser off, as before the pen's 30 % default: with it, at 110 %
        // one edge pixel mid-stroke changes shade at pen-up, pans or not (the
        // shift this test is about is hundreds).
        final frames = await f.draw(points, streamline: 0);
        f.lift(scene.model);
        frames
          ..add(await f.frame())
          ..addAll(await f.until(() => settledTiles(scene)));
        // Not a pixel's shade changes: no shift by a fraction of a pixel.
        for (var k = frames.length - 3; k < frames.length; k++) {
          final shifted = lostInk(
            frames[k - 1],
            frames[k],
            near: 0,
            by: 40,
            except: endOf(f, points),
          );
          expect(shifted, 0, reason: 'frame $k shifted $shifted px of ink');
        }
        scene.dispose();
      });
    });
  }
}
