// The pen never flickers around zooms either: rendered frame by frame,
// crossing between the level-of-detail rasters (zoomed far out) and the
// tiles never shows the ink missing for a frame, whatever is rendered yet.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';

import 'pen_flicker_frames_test.dart' show framesOf;
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
}
