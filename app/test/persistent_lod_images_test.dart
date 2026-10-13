import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/raster_store.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/chunk_digest.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/stroke_chunks.dart';
import 'package:len/ink/images/element_images.dart';
import 'package:len/ink/render/chunk_picture_cache.dart';
import 'package:len/ink/render/chunk_raster_cache.dart';
import 'package:len/ink/render/ink_painters.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/viewport.dart';

import 'images_test.dart' show imageElement, pngOf;
import 'support/canvas_fixtures.dart';
import 'support/ink_scene.dart';

const _size = Size(400, 300);

/// A canvas with images at 10 %, drawn from [store] ([stored]) or loaded.
class _View {
  _View(AppDatabase db, this.images, {RasterStore? store, bool stored = true}) {
    final strokes = StrokeRepository(db, deviceId: 'd');
    model = SurfaceModel(
      surfaceId: 's',
      repository: strokes,
      elementRepository: ElementRepository(db, deviceId: 'd'),
      reader: strokes,
      maxLoadedChunks: 1 << 20,
      rasterStore: store,
      images: images,
    );
    viewport
      ..setSize(_size)
      ..zoomAt(Offset.zero, 0.1)
      ..panBy(const Offset(40, 40));
    stored ? model.showStored(viewport.visibleWorld) : model.ensureLoaded(viewport.visibleWorld);
  }

  final ElementImages images;
  late final SurfaceModel model;
  final viewport = ViewportController(minScale: 0.01);
  late final pictures = ChunkPictureCache(model, devicePixelRatio: 1);
  late final rasters = ChunkRasterCache(pictures, maxBytes: 64 << 20);

  CommittedInkPainter get painter =>
      CommittedInkPainter(model: model, cache: pictures, viewport: viewport, rasters: rasters);

  /// Paints until frames stop changing and nothing is pending.
  Future<void> warm() async {
    var stable = 0, previous = -1;
    for (var i = 0; i < 200; i++) {
      final canvas = CountingCanvas();
      painter.paint(canvas, _size);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await settle(() => !rasters.isBusy && !model.isLoading);
      stable = canvas.images == previous && canvas.pictures == 0 ? stable + 1 : 0;
      if (stable == 3) return;
      previous = canvas.images;
    }
    fail('never settled');
  }

  Future<Uint8List> render() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
    painter.paint(canvas, _size);
    final image = await recorder.endRecording().toImage(400, 300);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    return bytes.buffer.asUint8List();
  }

  void dispose() {
    rasters.dispose();
    pictures.dispose();
    model.dispose();
  }
}

void main() {
  testWidgets('a chunk with an image is stored once its image is decoded, not before', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final db = AppDatabase.inMemory();
      final store = MemoryRasterStore();
      final blobs = <String, Uint8List>{};
      ElementImages images() =>
          ElementImages(read: (sha) async => blobs[sha], fetch: (_) async => false);
      StrokeRepository(
        db,
        deviceId: 'd',
      ).save(scribbles(300, const Rect.fromLTWH(0, 0, 3000, 2000), seed: 3, points: 12));
      final photo = imageElement('i', const Rect.fromLTWH(600, 600, 800, 400), blob: 'photo');
      ElementRepository(db, deviceId: 'd').save([photo]);
      final withImage = ElementChunks.of(photo);
      bool storedAny(Iterable<ChunkKey> chunks) =>
          store.names.any((n) => chunks.any((k) => n.startsWith('s_${k.x}_${k.y}_')));

      // The blob has not arrived (another device added it): placeholders,
      // drawn but never stored.
      final first = _View(db, images(), store: store);
      await first.warm();
      expect(store.names, isNotEmpty);
      expect(storedAny(withImage), isFalse);

      // It arrives (a sync fetched it): decoded, redrawn and stored.
      blobs['photo'] = pngOf(400, 200);
      first.images.retryMissing();
      await first.warm();
      expect(storedAny(withImage), isTrue);
      first.dispose();

      // Reopened far out: drawn from the store, nothing loaded, the image
      // as decoded.
      final reopened = _View(db, images(), store: store);
      await reopened.warm();
      expect(reopened.model.loadedElementCount, 0);
      expect(reopened.model.loadedStrokeCount, 0);
      final truth = _View(db, images(), stored: false);
      await truth.warm();
      final (_, off) = imageDiff(await reopened.render(), await truth.render());
      expect(off, lessThan(0.001));
      reopened.dispose();
      truth.dispose();

      // The digest covers the element's value, which names its blob by
      // content hash: another image in the same place is another raster.
      final other = imageElement('i', photo.rect, blob: 'other');
      expect(ChunkDigest.ofElement(other) == ChunkDigest.ofElement(photo), isFalse);
      db.close();
    });
  });
}
