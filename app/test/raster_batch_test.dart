import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/render/raster_batch.dart';

ui.Picture _filled(int width, int height, ui.Color color) {
  final recorder = ui.PictureRecorder();
  // Bigger than asked: the atlas clips each picture to its own place.
  ui.Canvas(recorder)
      .drawRect(ui.Rect.fromLTWH(-20, -20, width + 40.0, height + 40.0), ui.Paint()..color = color);
  return recorder.endRecording();
}

/// The colour of [raster] at ([x], [y]) of its own pixels.
Future<int> _pixel(RasterImage raster, int x, int y) async {
  final data = (await raster.image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final at =
      ((raster.source.top.round() + y) * raster.image.width + raster.source.left.round() + x);
  return data.getUint32(at * 4);
}

void main() {
  test('natively each picture is an image of its own', () async {
    final batch = RasterBatch(batching: false);
    final picture = _filled(30, 20, const ui.Color(0xFFFF0000));
    final raster = await batch.rasterize(picture, 30, 20);
    expect((raster.image.width, raster.image.height), (30, 20));
    expect(raster.whole, isTrue);
    expect(raster.bytes, 30 * 20 * 4);
    raster.dispose();
    picture.dispose();
  });

  test('batched, the pictures of one turn share an atlas, each in its own place', () async {
    final batch = RasterBatch(batching: true, atlasSize: 128);
    const colours = [ui.Color(0xFFFF0000), ui.Color(0xFF00FF00), ui.Color(0xFF0000FF)];
    final sizes = [(40, 30), (64, 64), (20, 50)];
    final pictures = [for (var i = 0; i < 3; i++) _filled(sizes[i].$1, sizes[i].$2, colours[i])];
    final rasters = await Future.wait([
      for (var i = 0; i < 3; i++) batch.rasterize(pictures[i], sizes[i].$1, sizes[i].$2),
    ]);
    expect(batch.readbacks, 1);
    final expected = [0xFF0000FF, 0x00FF00FF, 0x0000FFFF];
    for (var i = 0; i < 3; i++) {
      final r = rasters[i];
      expect((r.width, r.height), sizes[i]);
      expect(r.whole, isFalse);
      // Corners of its own place: its colour, none of its neighbours'.
      for (final (x, y) in [
        (0, 0),
        (r.width - 1, 0),
        (0, r.height - 1),
        (r.width - 1, r.height - 1),
      ]) {
        expect(await _pixel(r, x, y), expected[i], reason: 'raster $i at ($x, $y)');
      }
    }
    for (var i = 0; i < 3; i++) {
      for (var j = i + 1; j < 3; j++) {
        expect(rasters[i].source.overlaps(rasters[j].source), isFalse);
      }
    }
    // The atlas's memory is charged in shares.
    expect(rasters.fold(0, (sum, r) => sum + r.bytes), closeTo(128 * 128 * 4, 3));
    for (final r in rasters) {
      r.dispose();
    }
    for (final p in pictures) {
      p.dispose();
    }
  });

  test('what does not fit waits for the next atlas; an atlas-sized picture is one', () async {
    final batch = RasterBatch(batching: true, atlasSize: 64);
    final pictures = [
      for (var i = 0; i < 5; i++) _filled(40, 40, const ui.Color(0xFF808080)),
      _filled(64, 64, const ui.Color(0xFF808080)),
      _filled(100, 10, const ui.Color(0xFF808080)),
    ];
    final rasters = await Future.wait([
      for (var i = 0; i < 5; i++) batch.rasterize(pictures[i], 40, 40),
      batch.rasterize(pictures[5], 64, 64),
      batch.rasterize(pictures[6], 100, 10), // Larger than an atlas: alone, at once.
    ]);
    expect(batch.readbacks, 7);
    expect(rasters[5].whole, isTrue);
    expect((rasters[6].image.width, rasters[6].image.height), (100, 10));
    // A picture alone on an atlas is charged the whole atlas.
    expect(rasters[0].bytes, 64 * 64 * 4);
    for (final r in rasters) {
      r.dispose();
    }
    for (final p in pictures) {
      p.dispose();
    }
  });

  group('image', () {
    /// A picture of four [size]² quadrants: red, green / blue, white.
    ui.Picture quadrants(int width, int height) {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final w = width / 2, h = height / 2;
      canvas
        ..drawRect(ui.Rect.fromLTWH(0, 0, w, h), ui.Paint()..color = const ui.Color(0xFFFF0000))
        ..drawRect(ui.Rect.fromLTWH(w, 0, w, h), ui.Paint()..color = const ui.Color(0xFF00FF00))
        ..drawRect(ui.Rect.fromLTWH(0, h, w, h), ui.Paint()..color = const ui.Color(0xFF0000FF))
        ..drawRect(ui.Rect.fromLTWH(w, h, w, h), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
      return recorder.endRecording();
    }

    Future<void> expectQuadrants(ui.Image image, int width, int height) async {
      expect((image.width, image.height), (width, height));
      final data = (await image.toByteData())!;
      int at(int x, int y) => data.getUint32((y * width + x) * 4);
      for (final (x, y, colour) in [
        (0, 0, 0xFF0000FF),
        (width ~/ 2 - 1, height ~/ 2 - 1, 0xFF0000FF),
        (width ~/ 2, 0, 0x00FF00FF),
        (width - 1, height ~/ 2 - 1, 0x00FF00FF),
        (0, height - 1, 0x0000FFFF),
        (width - 1, height - 1, 0xFFFFFFFF),
        (width ~/ 2, height ~/ 2, 0xFFFFFFFF),
      ]) {
        expect(at(x, y), colour, reason: '($x, $y)');
      }
    }

    test('natively it is the picture made into an image', () async {
      final batch = RasterBatch(batching: false);
      final picture = quadrants(40, 30);
      final image = await batch.image(picture, 40, 30);
      await expectQuadrants(image, 40, 30);
      expect(batch.imageNow(picture, 40, 30), isA<ui.Image>());
      image.dispose();
      picture.dispose();
    });

    test('batched, a small picture is cut from an atlas it shared', () async {
      final batch = RasterBatch(batching: true, atlasSize: 128);
      final pictures = [quadrants(40, 30), quadrants(50, 64)];
      final images = await Future.wait([
        batch.image(pictures[0], 40, 30),
        batch.image(pictures[1], 50, 64),
      ]);
      expect(batch.readbacks, 1);
      await expectQuadrants(images[0], 40, 30);
      await expectQuadrants(images[1], 50, 64);
      final later = batch.imageNow(pictures[0], 40, 30);
      expect(later, isA<Future<ui.Image>>());
      (await later).dispose();
      for (final i in images) {
        i.dispose();
      }
      for (final p in pictures) {
        p.dispose();
      }
    });

    test('batched, a large picture is stitched from atlas-sized slices', () async {
      final batch = RasterBatch(batching: true, atlasSize: 64);
      final picture = quadrants(150, 70);
      final image = await batch.image(picture, 150, 70);
      expect(batch.readbacks, 6); // 3 × 2 slices, every one atlas-sized.
      await expectQuadrants(image, 150, 70);
      image.dispose();
      picture.dispose();
    });
  });
}
