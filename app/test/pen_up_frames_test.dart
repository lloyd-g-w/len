// Pen-up never flickers: every frame from the last live one to the settled
// ink shows the stroke just drawn, once, where it was (the live stroke
// hands over to the committed ink in the same frame, and tiles or rasters
// that still predate it draw it as vectors — over them for pen ink,
// beneath them for the highlighter, as the live highlighter was). Checked
// on a canvas at several zooms and on a page of a continuous notebook,
// from tiles and from zoomed-out rasters.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/document/document_layout.dart';
import 'package:len/features/editor/document/document_painters.dart';
import 'package:len/features/editor/document/document_surfaces.dart';
import 'package:len/features/editor/document/page_viewport.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/pen/pen_config.dart';
import 'package:len/ink/render/ink_painters.dart';
import 'package:len/ink/render/live_stroke.dart';
import 'package:len/ink/render/stroke_renderer.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/viewport.dart';

import 'support/canvas_fixtures.dart';
import 'support/ink_scene.dart';

/// A long wavy stroke (world units), crossing many tiles.
List<StrokePoint> _wave() => [
  for (var i = 0; i <= 240; i++)
    StrokePoint(30 + i * 2.2, 120 + 90 * (i / 240) + 18 * ((i % 40) / 40 - 0.5).abs(), 0.55),
];

/// Pen ink already on the surface, beneath and around the new stroke.
List<Stroke> _background(String surfaceId) => [
  for (final s in scribbles(300, const Rect.fromLTWH(0, 0, 600, 400), seed: 4))
    if (!s.tool.isHighlighter)
      Stroke(
        id: s.id,
        surfaceId: surfaceId,
        tool: s.tool,
        color: s.color,
        width: s.width,
        points: s.points,
        createdAt: s.createdAt,
        style: s.style,
      ),
];

/// Where a stroke is drawn: the committed ink's painter, the model it is
/// committed to and the viewport the live ink is drawn through.
abstract class _Stage {
  Size get size;
  double get dpr;
  ViewportController get viewport;
  SurfaceModel get model;
  void paintInk(Canvas canvas);

  /// Checks how the first frame after pen-up drew the new stroke.
  void checkHandover(InkTool tool) {}

  /// Whether nothing is pending and the ink is drawn from its own images.
  bool get settled;
  Future<void> warm();
  void dispose();
}

/// A canvas surface ([InkScene]: tiles) at [scale].
class _CanvasStage extends _Stage {
  _CanvasStage({required double scale, required this.dpr})
    : scene = InkScene(_background('s'), scale: scale, dpr: dpr);

  final InkScene scene;
  @override
  final double dpr;
  @override
  Size get size => scene.size;
  @override
  ViewportController get viewport => scene.viewport;
  @override
  SurfaceModel get model => scene.model;
  @override
  void paintInk(Canvas canvas) => scene.painter().paint(canvas, size);

  @override
  void checkHandover(InkTool tool) {
    // The tiles kept their images and drew the stroke as a vector: over
    // them (pen), or beneath them (highlighter).
    final paint = scene.tiles.lastPaint;
    expect(tool.isHighlighter ? paint.underlayStrokes : paint.overlayStrokes, greaterThan(0));
    expect(paint.vectorTiles, 0);
  }

  @override
  bool get settled {
    final paint = scene.tiles.lastPaint;
    return !scene.busy &&
        paint.staleImages == 0 &&
        paint.overlayStrokes == 0 &&
        paint.underlayStrokes == 0 &&
        paint.vectorTiles == 0;
  }

  @override
  Future<void> warm() => scene.warm();
  @override
  void dispose() => scene.dispose();
}

/// The second page of a continuous two-page notebook at [scale], the first
/// page's end in view above it (tiles, or zoomed out far, chunk rasters).
class _PageStage extends _Stage {
  _PageStage({required double scale}) {
    repository.save(_background('p1'));
    final frame = layout.frameOf(1)!;
    document
      ..setSize(size)
      ..setView(scale: scale, offset: Offset(20, 60 - frame.top * scale));
    pageViewport.showPage(frame);
  }

  @override
  final size = const Size(600, 400);
  @override
  double get dpr => 1;
  final db = AppDatabase.inMemory();
  late final repository = StrokeRepository(db, deviceId: 'd');
  final pages = [
    for (var i = 0; i < 2; i++)
      NotebookPage(
        id: 'p$i',
        notebookId: 'nb',
        sortKey: i.toDouble(),
        width: 794,
        height: 1123,
        paper: Paper(PaperStyle.blank),
      ),
  ];
  late final layout = DocumentLayout.continuous([for (final p in pages) p.size]);
  late final surfaces = DocumentSurfaces(repository);
  final document = ViewportController(minScale: 0.05, maxScale: 8);
  late final pageViewport = PageViewport(document);

  @override
  ViewportController get viewport => pageViewport;
  @override
  SurfaceModel get model => surfaces.peek('p1')!.model;

  @override
  void paintInk(Canvas canvas) {
    final ahead = DocumentLayout.lookahead(document.visibleWorld);
    surfaces.showPages({
      for (final i in layout.visiblePages(ahead))
        pages[i].id: ahead.shift(-layout.frameOf(i)!.topLeft),
    });
    DocumentInkPainter(
      layout: layout,
      pages: pages,
      surfaces: surfaces,
      viewport: document,
    ).paint(canvas, size);
  }

  bool get _busy =>
      surfaces.all.any((s) => s.tiles.isBusy || s.rasters.isBusy || s.model.isLoading);

  @override
  bool get settled {
    if (_busy) return false;
    final probe = CountingCanvas();
    paintInk(probe);
    return probe.pictures == 0 && probe.paths == 0;
  }

  @override
  Future<void> warm() async {
    for (var i = 0; i < 60; i++) {
      paintInk(CountingCanvas());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await settle(() => !_busy);
      if (i > 1 && settled) return;
    }
    fail('the pages never settled');
  }

  @override
  void dispose() {
    pageViewport.dispose();
    surfaces.dispose();
    db.close();
  }
}

/// Draws [tool]'s stroke live on [stage], lifts the pen and returns every
/// frame, the live ones' last first.
Future<List<Uint8List>> _frames(_Stage stage, InkTool tool) async {
  await stage.warm();
  final viewport = stage.viewport;
  final config = PenConfig.defaultsFor(tool);
  final style = config.styleFor(tool).copyWith(unit: 1 / viewport.scale);
  final live = LiveInk()..begin(tool: tool, color: config.color, width: config.width, style: style);
  final clip = viewport.contentBounds;
  final below = LiveInkPainter(live: live, viewport: viewport, clip: clip, belowInk: true);
  final above = LiveInkPainter(live: live, viewport: viewport, clip: clip);

  Future<Uint8List> frame() async {
    final size = stage.size, dpr = stage.dpr;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(dpr)
      ..drawColor(Colors.white, BlendMode.src);
    below.paint(canvas, size);
    stage.paintInk(canvas);
    above.paint(canvas, size);
    final picture = recorder.endRecording();
    final image = await picture.toImage((size.width * dpr).ceil(), (size.height * dpr).ceil());
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
    surfaceId: stage.model.surfaceId,
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
  stage.model.addStroke(stroke);
  // The very next frame, then frames while the ink re-renders, until it
  // has settled.
  frames.add(await frame());
  stage.checkHandover(tool);
  for (var i = 0; i < 80 && !stage.settled; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 4));
    frames.add(await frame());
  }
  expect(stage.settled, isTrue, reason: 'the ink settled');
  frames.add(await frame());
  stage.dispose();
  return frames;
}

/// No frame after pen-up lacks the stroke or shows it twice.
void _expectSteady(List<Uint8List> frames) {
  final live = frames.first;
  for (final (k, f) in frames.indexed.skip(1)) {
    final (worst, share) = imageDiff(live, f, tolerance: 12);
    // The committed end may differ from the live tip by a few pixels; a
    // missing or doubled translucent stroke differs along its whole length.
    expect(share, lessThan(0.0015), reason: 'frame $k after pen-up: worst $worst');
  }
}

void main() {
  for (final tool in [InkTool.highlighter, InkTool.ballpoint]) {
    for (final (scale, dpr) in [(1.0, 1.0), (1.0, 2.0), (0.5, 1.0), (2.0, 1.0)]) {
      testWidgets('${tool.name} on a canvas at ${scale * 100} %, ${dpr}x dpr: steady pen-up', (
        tester,
      ) async {
        await tester.runAsync(() async {
          _expectSteady(await _frames(_CanvasStage(scale: scale, dpr: dpr), tool));
        });
      });
    }
    // 100 % and 60 %: tiles; 30 % and 15 %: chunk rasters.
    for (final scale in [1.0, 0.6, 0.3, 0.15]) {
      testWidgets('${tool.name} on a notebook page at ${scale * 100} %: steady pen-up', (
        tester,
      ) async {
        await tester.runAsync(() async {
          _expectSteady(await _frames(_PageStage(scale: scale), tool));
        });
      });
    }
  }
}
