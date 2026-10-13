import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/render/chunk_picture_cache.dart';
import 'package:len/ink/render/chunk_raster_cache.dart';
import 'package:len/ink/render/ink_painters.dart';
import 'package:len/ink/render/tiles/ink_tile_cache.dart';
import 'package:len/ink/render/tiles/tile_pool.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/viewport.dart';

import 'canvas_fixtures.dart';

/// Counts the draw calls a painter issues.
class CountingCanvas implements Canvas {
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

/// A canvas surface over [strokes] with its caches, viewed at [scale] with
/// [dpr] device pixels per logical pixel.
class InkScene {
  InkScene(
    List<Stroke> strokes, {
    double scale = 1,
    this.dpr = 1,
    Offset pan = Offset.zero,
    this.size = const Size(600, 400),
    TilePool? pool,
    bool lod = false,
    Duration settleDelay = const Duration(milliseconds: 20),
    Duration batchBudget = const Duration(milliseconds: 4),
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
      settleDelay: settleDelay,
      batchBudget: batchBudget,
    );
    rasters = lod ? ChunkRasterCache(pictures, maxBytes: 256 << 20) : null;
  }

  final double dpr;
  final Size size;
  final db = AppDatabase.inMemory();
  final viewport = ViewportController(minScale: 0.01);
  late final SurfaceModel model;
  late final pictures = ChunkPictureCache(model, devicePixelRatio: dpr);
  late final InkTileCache tiles;
  late final ChunkRasterCache? rasters;

  bool get busy => tiles.isBusy || (rasters?.isBusy ?? false);

  CommittedInkPainter painter({bool tiled = true}) => CommittedInkPainter(
    model: model,
    cache: pictures,
    viewport: viewport,
    tiles: tiled ? tiles : null,
    rasters: rasters,
    devicePixelRatio: dpr,
  );

  /// Paints until no tile render is pending.
  Future<void> warm() async {
    for (var i = 0; i < 50; i++) {
      painter().paint(CountingCanvas(), size);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await settle(() => !busy);
      painter().paint(CountingCanvas(), size);
      if (!busy && tiles.lastPaint.vectorTiles == 0 && tiles.lastPaint.overlayStrokes == 0) {
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
    rasters?.dispose();
    pictures.dispose();
    model.dispose();
    db.close();
  }
}

/// Largest per-channel difference and the share of pixels that differ by
/// more than [tolerance].
(int, double) imageDiff(Uint8List a, Uint8List b, {int tolerance = 8}) {
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
