import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/render/chunk_picture_cache.dart';
import 'package:len/ink/render/chunk_raster_cache.dart';
import 'package:len/ink/render/ink_painters.dart';
import 'package:len/ink/render/paper_painter.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/viewport.dart';

import 'support/canvas_fixtures.dart';

/// Counts the draw calls a painter issues.
class _CountingCanvas implements Canvas {
  int pictures = 0;
  int images = 0;

  @override
  void drawPicture(ui.Picture picture) => pictures++;

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) => images++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A surface over [strokes] with its caches, viewed at [scale].
class _Scene {
  _Scene(List<Stroke> strokes, {required double scale, required Size size, Offset? centre}) {
    model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
      reader: MemoryStrokeReader(strokes),
      maxLoadedChunks: 1 << 20,
    );
    viewport.setSize(size);
    viewport.zoomAt(Offset.zero, scale);
    final c = centre ?? Offset.zero;
    viewport.panBy(Offset(size.width / 2, size.height / 2) - viewport.toScreen(c));
    model.ensureLoaded(viewport.visibleWorld);
  }

  final db = AppDatabase.inMemory();
  final viewport = ViewportController(minScale: 0.01);
  late final SurfaceModel model;
  late final pictures = ChunkPictureCache(model);
  late final rasters = ChunkRasterCache(pictures, maxBytes: 256 << 20);

  CommittedInkPainter painter({required bool lod}) => CommittedInkPainter(
    model: model,
    cache: pictures,
    viewport: viewport,
    rasters: lod ? rasters : null,
  );

  /// Paints once so every visible raster is requested, then waits for them.
  Future<void> warmRasters() async {
    painter(lod: true).paint(_CountingCanvas(), viewport.size);
    await settle(() => !rasters.isBusy);
  }

  /// Renders paper + ink to an image, timing the GPU/raster side.
  Future<(ui.Image, Duration)> render({required bool lod}) async {
    final size = viewport.size;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    PaperPainter(viewport: viewport, style: PaperStyle.blank).paint(canvas, size);
    painter(lod: lod).paint(canvas, size);
    final picture = recorder.endRecording();
    final watch = Stopwatch()..start();
    final image = await picture.toImage(size.width.toInt(), size.height.toInt());
    final elapsed = watch.elapsed;
    picture.dispose();
    return (image, elapsed);
  }

  void dispose() {
    rasters.dispose();
    pictures.dispose();
    model.dispose();
    db.close();
  }
}

Future<Uint8List> _rgba(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();

void main() {
  test('raster level follows the on-screen chunk size', () {
    expect(ChunkRasterCache.levelFor(600), isNull);
    expect(ChunkRasterCache.levelFor(256), 256);
    expect(ChunkRasterCache.levelFor(100), 128);
    expect(ChunkRasterCache.levelFor(25.6), 32);
  });

  testWidgets('a chunk requested on every frame is rasterised once; bytes stay exact', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final strokes = scribbles(200, const Rect.fromLTWH(0, 0, 512, 512));
      final scene = _Scene(strokes, scale: 0.1, size: const Size(400, 400));
      const chunk = (x: 0, y: 0);
      // Request the same raster repeatedly while it is being made.
      for (var i = 0; i < 20; i++) {
        scene.rasters.imageFor(chunk, 64);
        await Future<void>.delayed(Duration.zero);
      }
      await settle(() => !scene.rasters.isBusy);
      expect(scene.rasters.imageFor(chunk, 64), isNotNull);
      expect(scene.rasters.length, 1);
      expect(scene.rasters.bytes, 64 * 64 * 4);
      scene.dispose();
    });
  });

  testWidgets('far zoom: paint work is bounded by visible chunks, not by strokes', (tester) async {
    await tester.runAsync(() async {
      // 50 000 scribbles over 25 600 × 16 000 world units: 1 600 chunks,
      // all visible at 5 % on a 1280 × 800 view.
      final strokes = scribbles(50000, const Rect.fromLTWH(0, 0, 25600, 16000));
      final scene = _Scene(
        strokes,
        scale: 0.05,
        size: const Size(1280, 800),
        centre: const Offset(12800, 8000),
      );
      final visible = scene.model.chunksIn(ChunkGrid.rangeFor(scene.viewport.visibleWorld));
      expect(scene.model.loadedStrokeCount, 50000);

      final record = Stopwatch()..start();
      final vector = _CountingCanvas();
      scene.painter(lod: false).paint(vector, scene.viewport.size);
      final recordTime = record.elapsed;
      expect(vector.pictures, visible.length);

      // With LOD, an uncached screen never records more than a few chunks
      // in one frame: the rest is filled in by background batches.
      final cold = _Scene(strokes, scale: 0.05, size: const Size(1280, 800));
      final coldCanvas = _CountingCanvas();
      final coldWatch = Stopwatch()..start();
      cold.painter(lod: true).paint(coldCanvas, cold.viewport.size);
      final coldFrame = coldWatch.elapsed;
      expect(coldCanvas.pictures, lessThanOrEqualTo(CommittedInkPainter.freshRecordingsPerFrame));
      cold.dispose();

      final warm = Stopwatch()..start();
      await scene.warmRasters();
      final warmTime = warm.elapsed;
      final lod = _CountingCanvas();
      final paintWatch = Stopwatch()..start();
      scene.painter(lod: true).paint(lod, scene.viewport.size);
      final lodPaint = paintWatch.elapsed;
      expect(lod.pictures, 0);
      expect(lod.images, visible.length);
      expect(scene.rasters.bytes, lessThanOrEqualTo(256 << 20));

      // Rasterising the frame: replaying 50k outlines vs 1 600 images.
      final (vectorImage, vectorRaster) = await scene.render(lod: false);
      final (lodImage, lodRaster) = await scene.render(lod: true);
      vectorImage.dispose();
      lodImage.dispose();
      // ignore: avoid_print
      print(
        'LOD benchmark: ${strokes.length} strokes, ${visible.length} chunks visible\n'
        '  vector: ${vector.pictures} pictures (${strokes.length} outlines), '
        'first-frame recording ${recordTime.inMilliseconds} ms, '
        'frame raster ${vectorRaster.inMilliseconds} ms\n'
        '  LOD: ${lod.images} images, cold frame ${coldFrame.inMilliseconds} ms, '
        'paint ${lodPaint.inMicroseconds} µs, frame raster ${lodRaster.inMilliseconds} ms, '
        'rasters made in ${warmTime.inMilliseconds} ms, ${scene.rasters.bytes >> 10} KiB',
      );
      expect(lodRaster, lessThan(vectorRaster));
      scene.dispose();
    });
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('far zoom: LOD rendering looks like the vector rendering', (tester) async {
    final sideBySide = await tester.runAsync(() async {
      final strokes = [
        ...scribbles(1500, const Rect.fromLTWH(0, 0, 3000, 1800), seed: 3, points: 24),
        // Long strokes crossing many chunk borders (seams would show here).
        for (var i = 0; i < 6; i++)
          Stroke(
            id: 'long$i',
            surfaceId: 's',
            tool: i.isEven ? InkTool.marker : InkTool.highlighter,
            color: i.isEven ? 0xFF283593 : 0x88FFD54F,
            width: i.isEven ? 14 : 40,
            points: [
              for (var t = 0; t <= 60; t++)
                StrokePoint(
                  t * 52.0,
                  200 + i * 260 + 120 * (t % 12 < 6 ? t % 6 : 6 - t % 6) / 6,
                  0.5,
                ),
            ],
            createdAt: 100000 + i,
          ),
      ];
      // 0.2 × 512 = 102 device pixels per chunk: the 128 px level.
      final scene = _Scene(
        strokes,
        scale: 0.2,
        size: const Size(640, 400),
        centre: const Offset(1550, 950),
      );
      await scene.warmRasters();
      final (vector, _) = await scene.render(lod: false);
      final (lod, _) = await scene.render(lod: true);

      // Side by side for a visual check: vector left, LOD right.
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..drawImage(vector, Offset.zero, Paint())
        ..drawImage(lod, const Offset(640, 0), Paint())
        ..drawRect(const Rect.fromLTWH(639, 0, 2, 400), Paint()..color = Colors.red);
      final sideBySide = await recorder.endRecording().toImage(1280, 400);
      final a = await _rgba(vector);
      final b = await _rgba(lod);
      var total = 0;
      var large = 0;
      for (var i = 0; i < a.length; i++) {
        final d = (a[i] - b[i]).abs();
        total += d;
        if (d > 64) large++;
      }
      final mean = total / a.length;
      // ignore: avoid_print
      print(
        'LOD vs vector: mean channel difference ${mean.toStringAsFixed(2)}, '
        '${(large / a.length * 100).toStringAsFixed(2)} % channels off by > 64',
      );
      vector.dispose();
      lod.dispose();
      scene.dispose();
      return (sideBySide, mean, large / a.length);
    });
    final (image, mean, outliers) = sideBySide!;
    await expectLater(image, matchesGoldenFile('goldens/lod_far_zoom.png'));
    // Hairlines resample slightly differently; misplaced or missing
    // rasters would differ by far more.
    expect(mean, lessThan(6));
    expect(outliers, lessThan(0.01));
  });

  testWidgets('edits invalidate rasters; memory stays within the budget', (tester) async {
    await tester.runAsync(() async {
      final strokes = scribbles(400, const Rect.fromLTWH(0, 0, 4096, 4096));
      final scene = _Scene(strokes, scale: 0.1, size: const Size(800, 600));
      final small = ChunkRasterCache(scene.pictures, maxBytes: 10 * 64 * 64 * 4);
      final painter = CommittedInkPainter(
        model: scene.model,
        cache: scene.pictures,
        viewport: scene.viewport,
        rasters: small,
      );
      painter.paint(_CountingCanvas(), scene.viewport.size);
      await settle(() => !small.isBusy);
      expect(small.length, 10); // 64 chunks visible, LRU keeps 10
      expect(small.bytes, 10 * 64 * 64 * 4);

      final cached = scene.model
          .chunksIn(ChunkGrid.rangeFor(scene.viewport.visibleWorld))
          .where((k) => small.imageFor(k, 64) != null);
      final chunk = cached.first;
      final stroke = scene.model.strokesInChunk(chunk).first;
      scene.model.eraseAlong(
        stroke.points.first.offset,
        stroke.points.last.offset,
        4,
        continueEdit: false,
      );
      expect(small.imageFor(chunk, 64), isNull);
      small.dispose();
      scene.dispose();
    });
  });
}
