// The pen never flickers around edits either: rendered frame by frame,
// erasing, undoing and redoing lose no ink but the edited strokes' (a
// pixel inked in frame N but not in N + 1, away from what the edit took),
// however many tiles the edit crosses and whatever the renders are doing.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/pen/eraser_config.dart';
import 'package:len/ink/undo_history.dart';

import 'pen_flicker_frames_test.dart' show background, framesOf, settledTiles, wave;
import 'support/ink_frames.dart';
import 'support/ink_scene.dart';

/// A long pen stroke over [background], crossing many tiles.
Stroke long({String id = 'long', double y = 120}) => Stroke(
  id: id,
  surfaceId: 's',
  tool: InkTool.ballpoint,
  color: 0xFF000000,
  width: 3,
  points: wave(y: y),
  createdAt: 1 << 41,
);

/// Device-pixel boxes covering [stroke]'s ink in [f]'s view: what an edit
/// taking it may take.
List<Rect> inkOf(InkFrames f, Stroke stroke) {
  final scale = f.viewport.scale;
  final r = stroke.width * scale + 2;
  final points = [for (final p in stroke.points) p.offset];
  return [
    f.around(points.last, r),
    for (var i = 0; i + 1 < points.length; i++)
      // Every 2 px along each segment, so the boxes join up.
      for (var k = 0, n = ((points[i + 1] - points[i]).distance * scale / 2).ceil(); k < n; k++)
        f.around(Offset.lerp(points[i], points[i + 1], k / n)!, r),
  ];
}

void main() {
  Future<void> edited(
    WidgetTester tester, {
    required void Function(InkScene scene) before,
    required void Function(InkScene scene) edit,
    required List<Stroke> Function(InkScene scene) taken,
    double dpr = 2,
    double scale = 1,
    bool held = false,
  }) async {
    await tester.runAsync(() async {
      final batch = HeldBatch();
      final scene = InkScene(background(), dpr: dpr, scale: scale, batch: batch);
      before(scene);
      await scene.warm();
      final f = framesOf(scene);
      final frames = [await f.frame()];
      final gone = taken(scene);
      // A busy raster thread: the edit's renders wait a few frames.
      batch.hold = held;
      edit(scene);
      for (var i = 0; i < (held ? 4 : 1); i++) {
        frames.add(await f.frame());
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
      batch.release();
      frames.addAll(await f.until(() => settledTiles(scene)));
      await expectNoLostInk(frames, except: [for (final s in gone) ...inkOf(f, s)]);
      scene.dispose();
    });
  }

  for (final held in [false, true]) {
    final busy = held ? ', renders held' : '';
    testWidgets('erasing a stroke over many tiles$busy: the rest of the ink stays', (tester) async {
      await edited(
        tester,
        held: held,
        before: (scene) => scene.model.addStroke(long()),
        edit: (scene) => scene.model.commit(InkEdit(removed: [scene.model.strokeById('long')!])),
        taken: (scene) => [scene.model.strokeById('long')!],
      );
    });

    testWidgets('erasing two strokes far apart (two tiles at most each)$busy: the rest stays', (
      tester,
    ) async {
      Stroke dot(String id, Offset at) => Stroke(
        id: id,
        surfaceId: 's',
        tool: InkTool.ballpoint,
        color: 0xFF000000,
        width: 3,
        points: [StrokePoint(at.dx, at.dy, .5), StrokePoint(at.dx + 12, at.dy + 4, .5)],
        createdAt: 1 << 41,
      );
      await edited(
        tester,
        held: held,
        before: (scene) => scene.model
          ..addStroke(dot('a', const Offset(40, 60)))
          ..addStroke(dot('b', const Offset(520, 330))),
        edit: (scene) => scene.model.commit(
          InkEdit(removed: [scene.model.strokeById('a')!, scene.model.strokeById('b')!]),
        ),
        taken: (scene) => [scene.model.strokeById('a')!, scene.model.strokeById('b')!],
      );
    });
  }

  testWidgets('pixel-erasing across many strokes: only what the eraser took goes', (tester) async {
    late List<Stroke> touched;
    await edited(
      tester,
      before: (_) {},
      edit: (scene) => scene.model.eraseAlong(
        const Offset(20, 200),
        const Offset(580, 210),
        6,
        continueEdit: false,
        mode: EraserMode.pixel,
      ),
      taken: (scene) {
        touched = scene.model.strokesNear(const Rect.fromLTRB(14, 194, 586, 216)).toList();
        // Only the eraser's band goes (and the cut ends reshape a little:
        // the fragments' outlines start and end there), the rest stays.
        return [
          Stroke(
            id: 'band',
            surfaceId: 's',
            tool: InkTool.ballpoint,
            color: 0,
            width: 20,
            points: [for (var x = 20.0; x <= 580; x += 4) StrokePoint(x, 200 + (x - 20) / 56, .5)],
            createdAt: 0,
          ),
        ];
      },
    );
    expect(touched, isNotEmpty);
  });

  testWidgets('undoing and redoing a stroke over many tiles: the rest stays, redo never blinks', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final scene = InkScene(background(), dpr: 2);
      scene.model.addStroke(long());
      await scene.warm();
      final f = framesOf(scene);
      final stroke = scene.model.strokeById('long')!;
      var frames = [await f.frame()];
      scene.model.undo();
      frames
        ..add(await f.frame())
        ..addAll(await f.until(() => settledTiles(scene)));
      await expectNoLostInk(frames, except: inkOf(f, stroke), what: 'undo frame');
      frames = [await f.frame()];
      scene.model.redo();
      frames
        ..add(await f.frame())
        ..addAll(await f.until(() => settledTiles(scene)));
      await expectNoLostInk(frames, what: 'redo frame');
      scene.dispose();
    });
  });

  testWidgets('undoing a move of many strokes: nothing else blinks', (tester) async {
    await tester.runAsync(() async {
      final scene = InkScene(background(), dpr: 2);
      await scene.warm();
      final moved = [
        for (final s in scene.model.strokesNear(const Rect.fromLTWH(0, 0, 600, 400)))
          if (s.bounds.top > 120 && s.bounds.bottom < 260) s,
      ];
      final shifted = [
        for (final s in moved)
          s.withPoints([
            for (final p in s.points) StrokePoint(p.x + 30, p.y + 40, p.pressure),
          ], id: '${s.id}-moved'),
      ];
      scene.model.commit(InkEdit(removed: moved, added: shifted));
      await scene.warm();
      final f = framesOf(scene);
      final frames = [await f.frame()];
      scene.model.undo();
      frames
        ..add(await f.frame())
        ..addAll(await f.until(() => settledTiles(scene)));
      await expectNoLostInk(frames, except: [for (final s in shifted) ...inkOf(f, s)]);
      scene.dispose();
    });
  });
}
