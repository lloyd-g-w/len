// The whole editor, frame by frame: strokes written with a stylus or a
// mouse lose no ink from one frame to the next — while drawn, at pen-up
// and in the frames after (the commit, its write to the database, the
// tiles taking it) — composited as the screen is (every layer, repaint
// boundary and page), on pages and canvases, at fractional device-pixel
// ratios, in split view and with strokes in quick succession.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/notebook.dart';

import 'document_editor_test.dart' show closeEditor, pumpEditor;
import 'split_view_test.dart' show paneOf, pumpWorkspace;
import 'support/ink_frames.dart';

/// The screen as composited now (physical pixels).
Future<Frame> grab(WidgetTester tester) async {
  final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
  final size = tester.view.physicalSize;
  final frame = await tester.runAsync(() async {
    final image = await layer.toImage(Offset.zero & size);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final frame = Frame(Uint8List.fromList(bytes.buffer.asUint8List()), image.width, image.height);
    image.dispose();
    return frame;
  });
  return frame!;
}

/// Lets tile renders land (real time), then builds a frame.
Future<void> settleFrame(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(milliseconds: 16));
}

/// Writes [strokes] wavy strokes from [start] (logical px, each below the
/// last) with [kind], one move a frame, the next stroke starting the frame
/// after the last lifts; then frames while the ink settles. Expects that
/// no frame lost ink the one before it showed, beyond the pen's tip.
Future<void> writeAndWatch(
  WidgetTester tester,
  Offset start, {
  PointerDeviceKind kind = PointerDeviceKind.stylus,
  int strokes = 1,
}) async {
  final dpr = tester.view.devicePixelRatio;
  for (var i = 0; i < 6; i++) {
    await settleFrame(tester);
  }
  final frames = [await grab(tester)];
  final tips = <Offset>[start];
  var ms = 1000;
  for (var s = 0; s < strokes; s++) {
    final from = start + Offset(0, s * 40.0);
    final pen = await tester.createGesture(kind: kind);
    await pen.down(from, timeStamp: Duration(milliseconds: ms += 8));
    await tester.pump(const Duration(milliseconds: 8));
    tips.add(from);
    frames.add(await grab(tester));
    for (var i = 1; i <= 48; i++) {
      final at = from + Offset(i * 5.0, 20 * ((i % 12) / 12 - 0.5).abs() + i * 0.6);
      await pen.moveTo(at, timeStamp: Duration(milliseconds: ms += 8));
      await tester.pump(const Duration(milliseconds: 8));
      tips.add(at);
      frames.add(await grab(tester));
    }
    await pen.up(timeStamp: Duration(milliseconds: ms += 8));
    await tester.pump(const Duration(milliseconds: 8));
    tips.add(tips.last);
    frames.add(await grab(tester));
  }
  for (var i = 0; i < 10; i++) {
    await settleFrame(tester);
    tips.add(tips.last);
    frames.add(await grab(tester));
  }
  // Where the ink is (the chrome may change with the pen: tool slots, hints).
  final area = Rect.fromPoints(
    (start - const Offset(40, 40)) * dpr,
    (start + Offset(300, 40.0 * strokes + 80)) * dpr,
  );
  for (var k = 1; k < frames.length; k++) {
    Rect near(Offset tip) => Rect.fromCircle(center: tip * dpr, radius: 14 * dpr);
    final lost = lostInk(
      frames[k - 1],
      frames[k],
      except: [near(tips[k - 1]), near(tips[k])],
      within: area,
    );
    final dump = Platform.environment['INK_FRAMES_DUMP'];
    if (lost > 0 && dump != null) {
      await tester.runAsync(() async {
        await frames[k - 1].save('$dump/editor_${k - 1}.png');
        await frames[k].save('$dump/editor_$k.png');
      });
    }
    expect(lost, 0, reason: 'frame $k lost $lost px of ink');
  }
  // The strokes were drawn, and stayed.
  expect(
    lostInk(frames.last, frames.first, within: area),
    greaterThan(200 * strokes),
    reason: 'ink shows',
  );
  expect(tester.takeException(), isNull);
}

void main() {
  for (final kind in [PointerDeviceKind.stylus, PointerDeviceKind.mouse]) {
    testWidgets('a ${kind.name} stroke on a page loses no ink, frame by frame', (tester) async {
      await pumpEditor(tester);
      await writeAndWatch(tester, const Offset(260, 420), kind: kind);
      await closeEditor(tester);
    });
  }

  testWidgets('strokes in quick succession on a page, at 2.625x: no ink lost', (tester) async {
    await pumpEditor(tester, size: const Size(480, 720));
    tester.view
      ..devicePixelRatio = 2.625
      ..physicalSize = const Size(480, 720) * 2.625;
    await tester.pumpAndSettle();
    await writeAndWatch(tester, const Offset(80, 260), strokes: 3);
    await closeEditor(tester);
  });

  testWidgets('strokes in quick succession on a canvas: no ink lost', (tester) async {
    await pumpWorkspace(tester, kind: NotebookKind.canvas);
    // A first stroke: the empty canvas's hint goes.
    final pen = await tester.startGesture(const Offset(200, 600), kind: PointerDeviceKind.stylus);
    await pen.moveTo(const Offset(260, 620));
    await pen.up();
    await tester.pumpAndSettle();
    await writeAndWatch(tester, const Offset(400, 300), strokes: 3);
    await closeEditor(tester);
  });

  testWidgets('a stroke in split view: no ink lost', (tester) async {
    final (s, _, chemistry) = await pumpWorkspace(tester);
    s.openNotebooks.openSplit(chemistry.id);
    await tester.pumpAndSettle();
    final pane = tester.getRect(paneOf(0));
    await writeAndWatch(tester, pane.center - const Offset(120, 60), strokes: 2);
    await closeEditor(tester);
  });
}
