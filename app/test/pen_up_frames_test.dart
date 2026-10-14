// Pen-up never flickers: every frame from the last live one to the settled
// tiles shows the stroke just drawn, once, where it was (the live stroke
// hands over to the committed ink in the same frame, and tiles that still
// predate it draw it as vectors — over them for pen ink, beneath them for
// the highlighter, as the live highlighter was).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/pen/pen_config.dart';
import 'package:len/ink/render/ink_painters.dart';
import 'package:len/ink/render/live_stroke.dart';
import 'package:len/ink/render/stroke_renderer.dart';

import 'support/canvas_fixtures.dart';
import 'support/ink_scene.dart';

/// A long wavy stroke across the view (world units), crossing many tiles.
List<StrokePoint> _wave() => [
  for (var i = 0; i <= 240; i++)
    StrokePoint(30 + i * 2.2, 120 + 90 * (i / 240) + 18 * ((i % 40) / 40 - 0.5).abs(), 0.55),
];

/// Draws [tool]'s stroke live over a scene of pen ink, lifts the pen and
/// returns every frame, the live ones' last first.
Future<List<Uint8List>> _frames(InkTool tool, {required double dpr}) async {
  final background = [
    for (final s in scribbles(300, const Rect.fromLTWH(0, 0, 600, 400), seed: 4))
      if (!s.tool.isHighlighter) s,
  ];
  final scene = InkScene(background, dpr: dpr);
  await scene.warm();
  final config = PenConfig.defaultsFor(tool);
  final style = config.styleFor(tool).copyWith(unit: 1);
  final live = LiveInk()..begin(tool: tool, color: config.color, width: config.width, style: style);
  final below = LiveInkPainter(live: live, viewport: scene.viewport, belowInk: true);
  final above = LiveInkPainter(live: live, viewport: scene.viewport);

  Future<Uint8List> frame() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scene.dpr)
      ..drawColor(Colors.white, BlendMode.src);
    below.paint(canvas, scene.size);
    scene.painter().paint(canvas, scene.size);
    above.paint(canvas, scene.size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (scene.size.width * scene.dpr).ceil(),
      (scene.size.height * scene.dpr).ceil(),
    );
    picture.dispose();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    return bytes.buffer.asUint8List();
  }

  final points = _wave();
  for (var n = 0; n < points.length; n += 8) {
    live.addAll(points.sublist(n, (n + 8).clamp(0, points.length)));
    await frame(); // Built as drawn: frozen pieces and a tail.
  }
  final frames = [await frame()];
  // Pen-up, as `InkDrawing` commits: the live outline is adopted.
  final committed = live.finish();
  final stroke = Stroke(
    id: 'new',
    surfaceId: 's',
    tool: tool,
    color: config.color,
    width: config.width,
    style: style,
    points: committed,
    createdAt: 1 << 41,
  );
  final path = LiveStrokeBuilder.finishLive(
    live,
    committed,
    width: stroke.width,
    style: stroke.style,
  );
  if (path != null) StrokeRenderer.adopt(stroke, path);
  scene.model.addStroke(stroke);
  // The very next frame, then frames while the tiles re-render, until they
  // have settled.
  frames.add(await frame());
  // The tiles kept their images and drew the stroke as a vector: over them
  // (pen), or beneath them (highlighter).
  final paint = scene.tiles.lastPaint;
  expect(tool.isHighlighter ? paint.underlayStrokes : paint.overlayStrokes, greaterThan(0));
  expect(paint.vectorTiles, 0);
  for (var i = 0; i < 60; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 4));
    frames.add(await frame());
    if (!scene.busy &&
        scene.tiles.lastPaint.staleImages == 0 &&
        scene.tiles.lastPaint.overlayStrokes == 0 &&
        scene.tiles.lastPaint.underlayStrokes == 0 &&
        scene.tiles.lastPaint.vectorTiles == 0) {
      break;
    }
  }
  expect(scene.busy, isFalse, reason: 'the tiles settled');
  frames.add(await frame());
  scene.dispose();
  return frames;
}

void main() {
  for (final tool in [InkTool.highlighter, InkTool.ballpoint]) {
    for (final dpr in [1.0, 2.0]) {
      testWidgets('${tool.name} at ${dpr}x dpr: no frame without it, none with it twice', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final frames = await _frames(tool, dpr: dpr);
          final live = frames.first;
          for (final (k, f) in frames.indexed.skip(1)) {
            final (worst, share) = imageDiff(live, f, tolerance: 12);
            // The committed end may differ from the live tip by a few
            // pixels; a missing or doubled translucent stroke differs along
            // its whole length.
            expect(share, lessThan(0.0015), reason: 'frame $k after pen-up: worst $worst');
          }
        });
      });
    }
  }
}
