import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/stroke_chunks.dart';
import 'package:len/ink/render/chunk_picture_cache.dart';
import 'package:len/ink/render/ink_painters.dart';
import 'package:len/ink/render/tiles/ink_tile_cache.dart';
import 'package:len/ink/render/tiles/tile_pool.dart';
import 'package:len/ink/render/tiles/tile_space.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/undo_history.dart';
import 'package:len/ink/viewport.dart';

import 'support/canvas_fixtures.dart';

/// Counts the draw calls a painter issues.
class _CountingCanvas implements Canvas {
  int pictures = 0;
  int images = 0;
  int paths = 0;

  @override
  void drawPicture(ui.Picture picture) => pictures++;

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) => images++;

  @override
  void drawPath(Path path, Paint paint) => paths++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A surface with its caches, viewed at [scale] with [dpr].
class _Scene {
  _Scene(
    List<Stroke> strokes, {
    double scale = 1,
    this.dpr = 1,
    Offset pan = Offset.zero,
    this.size = const Size(600, 400),
    TilePool? pool,
  }) {
    model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
      reader: MemoryStrokeReader(strokes),
      maxLoadedChunks: 1 << 20,
    );
    viewport
      ..setSize(size)
      ..zoomAt(Offset.zero, scale)
      ..panBy(pan);
    model.ensureLoaded(viewport.visibleWorld);
    tiles = InkTileCache(
      pictures,
      pool: pool ?? TilePool(),
      settleDelay: const Duration(milliseconds: 20),
    );
  }

  final double dpr;
  final Size size;
  final db = AppDatabase.inMemory();
  final viewport = ViewportController(minScale: 0.01);
  late final SurfaceModel model;
  late final pictures = ChunkPictureCache(model, devicePixelRatio: dpr);
  late final InkTileCache tiles;

  CommittedInkPainter painter({bool tiled = true}) => CommittedInkPainter(
    model: model,
    cache: pictures,
    viewport: viewport,
    tiles: tiled ? tiles : null,
    devicePixelRatio: dpr,
  );

  /// Paints until no tile render is pending.
  Future<void> warm() async {
    for (var i = 0; i < 50; i++) {
      painter().paint(_CountingCanvas(), size);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await settle(() => !tiles.isBusy);
      painter().paint(_CountingCanvas(), size);
      if (!tiles.isBusy &&
          tiles.lastPaint.vectorTiles == 0 &&
          tiles.lastPaint.overlayStrokes == 0) {
        return;
      }
    }
    fail('tiles never settled');
  }

  /// Renders the committed ink in device pixels.
  Future<Uint8List> render({bool tiled = true}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(dpr)
      ..drawColor(Colors.white, BlendMode.src);
    painter(tiled: tiled).paint(canvas, size);
    final picture = recorder.endRecording();
    final image = await picture.toImage((size.width * dpr).ceil(), (size.height * dpr).ceil());
    picture.dispose();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    return bytes.buffer.asUint8List();
  }

  void dispose() {
    tiles.dispose();
    pictures.dispose();
    model.dispose();
    db.close();
  }
}

/// Largest per-channel difference and the share of pixels that differ by
/// more than [tolerance].
(int, double) _diff(Uint8List a, Uint8List b, {int tolerance = 8}) {
  var worst = 0, off = 0;
  for (var i = 0; i < a.length; i += 4) {
    var d = 0;
    for (var c = 0; c < 4; c++) {
      final x = (a[i + c] - b[i + c]).abs();
      if (x > d) d = x;
    }
    if (d > worst) worst = d;
    if (d > tolerance) off++;
  }
  return (worst, off / (a.length / 4));
}

Stroke _line(String id, Offset from, Offset to, {int createdAt = 1 << 40, InkTool? tool}) => Stroke(
  id: id,
  surfaceId: 's',
  tool: tool ?? InkTool.ballpoint,
  color: 0xFFC62828,
  width: 4,
  points: [
    for (var t = 0; t <= 20; t++)
      StrokePoint(from.dx + (to.dx - from.dx) * t / 20, from.dy + (to.dy - from.dy) * t / 20, .6),
  ],
  createdAt: createdAt,
);

void main() {
  test('tile space: tiles sit on whole device pixels', () {
    final space = TileSpace.of(2.5, const Offset(100.3, -7.75));
    expect(space.phase.dx, closeTo(.3, 1e-9));
    expect(space.phase.dy, closeTo(.25, 1e-9));
    final rect = space.worldRectOf((x: 1, y: -2));
    // Device x of the tile's left edge relative to floor(origin) is a whole
    // multiple of the tile size.
    expect(rect.left * space.k + space.phase.dx, closeTo(TileSpace.size.toDouble(), 1e-9));
    expect(space.covering(rect.deflate(1)).toList(), [(x: 1, y: -2)]);
  });

  testWidgets('tiles look like the vector rendering (1×, 2× dpr, fractional pan)', (tester) async {
    await tester.runAsync(() async {
      final strokes = scribbles(600, const Rect.fromLTWH(0, 0, 900, 700), seed: 5, points: 16);
      for (final (scale, dpr, pan) in [
        (1.0, 1.0, Offset.zero),
        (1.37, 2.125, const Offset(-13.3, 7.61)),
      ]) {
        final scene = _Scene(strokes, scale: scale, dpr: dpr, pan: pan);
        final vector = await scene.render(tiled: false);
        await scene.warm();
        final tiled = await scene.render();
        expect(scene.tiles.lastPaint.images, greaterThan(0));
        expect(scene.tiles.lastPaint.vectorTiles, 0);
        final (worst, share) = _diff(vector, tiled);
        // Same rasteriser, same pixel grid: at most rounding differences.
        expect(share, lessThan(0.001), reason: 'scale $scale dpr $dpr worst $worst');
        scene.dispose();
      }
    });
  });

  testWidgets('a settled frame draws only images, however much ink', (tester) async {
    await tester.runAsync(() async {
      final strokes = scribbles(5000, const Rect.fromLTWH(0, 0, 1200, 900), points: 12);
      final scene = _Scene(strokes, size: const Size(1200, 900));
      await scene.warm();
      final canvas = _CountingCanvas();
      scene.painter().paint(canvas, scene.size);
      expect(canvas.pictures, 0);
      expect(canvas.paths, 0);
      // 1200 × 900 px in 512 px tiles: 3 × 2 (+ partial) tiles.
      expect(canvas.images, lessThanOrEqualTo(9));
      scene.dispose();
    });
  });

  testWidgets('pen-up: the committed stroke is drawn in the very next frame, then baked in', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final strokes = scribbles(800, const Rect.fromLTWH(0, 0, 600, 400), seed: 2);
      final scene = _Scene(strokes);
      await scene.warm();
      final before = await scene.render();
      final stroke = _line('new', const Offset(40, 300), const Offset(560, 330));
      scene.model.addStroke(stroke);
      // Same frame: tiles stay, the stroke is drawn over them as a vector.
      final canvas = _CountingCanvas();
      scene.painter().paint(canvas, scene.size);
      expect(canvas.pictures, 0, reason: 'no chunk re-recorded or replayed');
      expect(scene.tiles.lastPaint.vectorTiles, 0);
      expect(scene.tiles.lastPaint.overlayStrokes, greaterThan(0));
      final overlaid = await scene.render();
      expect(_diff(before, overlaid).$2, greaterThan(0.001), reason: 'stroke visible');
      // Afterwards it is part of the tiles; the picture matches the vectors.
      await scene.warm();
      expect(scene.tiles.lastPaint.overlayStrokes, 0);
      final baked = await scene.render();
      final vector = await scene.render(tiled: false);
      expect(_diff(baked, vector).$2, lessThan(0.001));
      expect(_diff(baked, overlaid).$2, lessThan(0.001));
      scene.dispose();
    });
  });

  testWidgets('erase and undo re-render only the affected tiles, correctly', (tester) async {
    await tester.runAsync(() async {
      final strokes = scribbles(300, const Rect.fromLTWH(0, 0, 1500, 1000), seed: 4);
      final scene = _Scene(strokes, size: const Size(1500, 1000));
      await scene.warm();
      final target = strokes.firstWhere((s) => s.bounds.right < 400 && s.bounds.bottom < 400);
      scene.model.commit(InkEdit(removed: [target]));
      scene.painter().paint(_CountingCanvas(), scene.size);
      // Only the tile(s) under the erased stroke fall back to vectors.
      expect(scene.tiles.lastPaint.vectorTiles, inInclusiveRange(1, 2));
      await scene.warm();
      expect(_diff(await scene.render(), await scene.render(tiled: false)).$2, lessThan(0.001));
      scene.model.undo();
      await scene.warm();
      expect(_diff(await scene.render(), await scene.render(tiled: false)).$2, lessThan(0.001));
      scene.dispose();
    });
  });

  testWidgets('zooming re-renders tiles sharp at the new scale', (tester) async {
    await tester.runAsync(() async {
      final strokes = scribbles(200, const Rect.fromLTWH(0, 0, 600, 400), seed: 6);
      final scene = _Scene(strokes);
      await scene.warm();
      for (final zoom in [4.0, 4.0]) {
        scene.viewport.zoomAt(const Offset(300, 200), zoom);
        // Mid-gesture: the old tiles are drawn scaled, nothing re-rendered.
        scene.painter().paint(_CountingCanvas(), scene.size);
        await scene.warm();
        final (worst, share) = _diff(await scene.render(), await scene.render(tiled: false));
        // Sharp (rendered at the new scale, not magnified): only the odd
        // anti-aliased edge pixel differs (float rounding of the transform).
        expect(share, lessThan(0.003), reason: 'at ${scene.viewport.scale}×, worst $worst');
      }
      scene.dispose();
    });
  });

  testWidgets('split view: two views of one shared model keep their own tiles, both current', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final strokes = scribbles(300, const Rect.fromLTWH(0, 0, 600, 400), seed: 3);
      final scene = _Scene(strokes);
      // A second view (another pane) of the same model with its own caches.
      final pictures = ChunkPictureCache(scene.model);
      final tiles = InkTileCache(pictures, settleDelay: const Duration(milliseconds: 20));
      CommittedInkPainter other() => CommittedInkPainter(
        model: scene.model,
        cache: pictures,
        viewport: scene.viewport,
        tiles: tiles,
        devicePixelRatio: 1,
      );
      Future<void> warmOther() async {
        for (var i = 0; i < 50 && (tiles.isBusy || i == 0); i++) {
          other().paint(_CountingCanvas(), scene.size);
          await settle(() => !tiles.isBusy);
          other().paint(_CountingCanvas(), scene.size);
        }
      }

      await scene.warm();
      await warmOther();
      // A stroke drawn in the first view shows in both, right away.
      scene.model.addStroke(_line('new', const Offset(40, 300), const Offset(560, 330)));
      scene.painter().paint(_CountingCanvas(), scene.size);
      other().paint(_CountingCanvas(), scene.size);
      expect(scene.tiles.lastPaint.overlayStrokes, greaterThan(0));
      expect(tiles.lastPaint.overlayStrokes, greaterThan(0));
      // Closing the second view leaves the first one working.
      await warmOther();
      tiles.dispose();
      pictures.dispose();
      await scene.warm();
      expect(_diff(await scene.render(), await scene.render(tiled: false)).$2, lessThan(0.001));
      scene.dispose();
    });
  });

  testWidgets('tile memory stays within the pool budget', (tester) async {
    await tester.runAsync(() async {
      const tileBytes = TileSpace.size * TileSpace.size * 4;
      final pool = TilePool(maxBytes: 4 * tileBytes);
      final strokes = scribbles(400, const Rect.fromLTWH(0, 0, 3000, 2000), seed: 8);
      final scene = _Scene(strokes, size: const Size(1000, 1000), pool: pool);
      for (var i = 0; i < 4; i++) {
        scene.viewport.panBy(const Offset(-512, 0));
        scene.painter().paint(_CountingCanvas(), scene.size);
        await settle(() => !scene.tiles.isBusy);
        expect(pool.bytes, lessThanOrEqualTo(4 * tileBytes));
      }
      scene.dispose();
    });
  });

  testWidgets('write-behind: a stroke is stored right after the frame that shows it', (
    tester,
  ) async {
    final db = AppDatabase.inMemory();
    final repository = StrokeRepository(db, deviceId: 'd');
    final model = SurfaceModel(surfaceId: 's', repository: repository, writeBehind: true);
    final stroke = _line('w', const Offset(0, 0), const Offset(100, 0));
    bool stored() => repository.loadChunks('s', StrokeChunks.of(stroke).toList()).isNotEmpty;
    model.addStroke(stroke);
    expect(model.strokeById('w'), isNotNull);
    expect(stored(), isFalse, reason: 'not written during the edit');
    await tester.pump();
    expect(stored(), isTrue);
    model.commit(InkEdit(removed: [stroke]));
    SurfaceModel.flushAll(); // E.g. before an export.
    expect(stored(), isFalse);
    model.dispose();
    db.close();
  });
}
