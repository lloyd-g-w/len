import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/image_data.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/features/editor/images/image_import.dart';
import 'package:len/features/editor/images/image_placement.dart';
import 'package:len/ink/elements/element_order.dart';
import 'package:len/ink/images/element_images.dart';
import 'package:len/ink/images/image_crop_session.dart';
import 'package:len/ink/render/chunk_picture_cache.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/selection/lasso.dart';
import 'package:len/ink/selection/selection_controller.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/undo_history.dart';

import 'data_test.dart' show FakeClock, stroke;

/// An encoded test image: a solid colour, or (with [alpha] < 255) a
/// translucent one.
Uint8List pngOf(int width, int height, {int r = 220, int g = 60, int b = 40, int alpha = 255}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(r, g, b, alpha));
  return img.encodePng(image);
}

/// A photo-like JPEG (a gradient).
Uint8List jpegOf(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (final p in image) {
    p
      ..r = p.x * 255 ~/ width
      ..g = p.y * 255 ~/ height
      ..b = 128;
  }
  return img.encodeJpg(image, quality: 90);
}

SurfaceElement imageElement(
  String id,
  Rect rect, {
  String blob = 'b',
  double z = -1,
  double rotation = 0,
  Rect? crop,
  int width = 400,
  int height = 200,
}) => SurfaceElement(
  id: id,
  surfaceId: 's',
  type: 'image',
  rect: rect,
  rotation: rotation,
  z: z,
  createdAt: 1,
  data: ImageData(blob: blob, width: width, height: height, crop: crop).toJson(),
);

void main() {
  group('ImageData', () {
    test('round-trips, omits a full crop and keeps unknown keys', () {
      const data = ImageData(blob: 'abc', width: 640, height: 480);
      final json = data.toJson({'future': 1});
      expect(json.containsKey('crop'), isFalse);
      expect(json['future'], 1);
      expect(ImageData.fromJson(json), data);
      final cropped = data.copyWith(crop: const Rect.fromLTWH(0.25, 0, 0.5, 1));
      expect(ImageData.fromJson(cropped.toJson()).crop, const Rect.fromLTWH(0.25, 0, 0.5, 1));
      expect(
        ImageData.fromJson(cropped.copyWith(crop: ImageData.full).toJson(cropped.toJson())),
        data,
      );
    });

    test('tolerates malformed fields', () {
      final data = ImageData.fromJson({
        'blob': 3,
        'width': 'wide',
        'height': -2,
        'crop': {'x': 0.9, 'y': -1, 'w': 5, 'h': 0.000001},
      });
      expect(data.blob, '');
      expect(data.width, 0);
      expect(data.height, 0);
      expect(data.crop.left, closeTo(0.9, 1e-9));
      expect(data.crop.right, lessThanOrEqualTo(1));
      expect(data.crop.height, greaterThanOrEqualTo(ImageData.minCrop - 1e-9));
      expect(ImageData.fromJson({'crop': 'x'}).crop, ImageData.full);
      expect(ImageData.normaliseCrop(const Rect.fromLTRB(-1e-9, 0, 1 + 1e-9, 1)), ImageData.full);
    });
  });

  group('ElementOrder', () {
    test('images stack on top of the layer beneath the ink, always below zero', () {
      var z = ElementOrder.onTopBelowInk(null);
      expect(z, ElementOrder.firstBelowInk);
      for (var i = 0; i < 5; i++) {
        final next = ElementOrder.onTopBelowInk(z);
        expect(next, greaterThan(z));
        expect(next, lessThan(0));
        z = next;
      }
      expect(ElementOrder.onTopBelowInk(-1), lessThan(0)); // Halves near zero.
      expect(ElementOrder.onTop(-5), 1);
      expect(ElementOrder.onTop(7), 8);
    });

    test('front / back move between layers and keep relative order', () {
      final a = imageElement('a', Rect.zero, z: -3);
      final b = imageElement('b', Rect.zero, z: -2);
      final front = ElementOrder.toFront([b, a], 4);
      expect([for (final e in front) (e.id, e.z)], [('a', 5.0), ('b', 6.0)]);
      expect(front.every((e) => !e.belowInk), isTrue);
      final back = ElementOrder.toBack(front, -10);
      expect([for (final e in back) (e.id, e.z)], [('a', -12.0), ('b', -11.0)]);
    });

    test('pasted copies stay in their layer', () {
      final below = imageElement('i', Rect.zero, z: -5);
      final above = imageElement('t', Rect.zero, z: 2);
      final z = ElementOrder.pasted([below, above], top: 2, topBelowInk: -5);
      expect(z[0], allOf(greaterThan(-5), lessThan(0)));
      expect(z[1], 3);
    });
  });

  group('ImageImport', () {
    test('sniffs formats by signature', () {
      expect(ImageImport.sniff(pngOf(2, 2)), 'image/png');
      expect(ImageImport.sniff(jpegOf(2, 2)), 'image/jpeg');
      expect(ImageImport.sniff(img.encodeGif(img.Image(width: 2, height: 2))), 'image/gif');
      final heic = Uint8List.fromList([0, 0, 0, 24, ...'ftypheic'.codeUnits, 0, 0, 0, 0]);
      expect(ImageImport.sniff(heic), 'image/heic');
      expect(ImageImport.sniff(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('keeps small PNG/JPEG files byte for byte', () async {
      final png = pngOf(300, 200);
      final prepared = await ImageImport.prepare(png);
      expect(prepared.bytes, same(png));
      expect((prepared.mime, prepared.width, prepared.height), ('image/png', 300, 200));
      final jpeg = await ImageImport.prepare(jpegOf(64, 48));
      expect((jpeg.mime, jpeg.width, jpeg.height), ('image/jpeg', 64, 48));
    });

    test('downscales huge images: opaque → JPEG, transparent → PNG', () async {
      final photo = await ImageImport.prepare(pngOf(5000, 100));
      expect((photo.mime, photo.width), ('image/jpeg', 4096));
      expect(photo.height, closeTo(82, 1));
      expect(ImageImport.sniff(photo.bytes), 'image/jpeg');
      final cutout = await ImageImport.prepare(pngOf(4200, 60, alpha: 128));
      expect((cutout.mime, cutout.width), ('image/png', 4096));
      final decoded = img.decodePng(cutout.bytes)!;
      expect(decoded.getPixel(10, 10).a, closeTo(128, 2));
    });

    test('takes the first frame of a GIF and rejects non-images', () async {
      final gif = img.encodeGif(img.Image(width: 30, height: 20));
      final prepared = await ImageImport.prepare(gif);
      expect(prepared.mime, isNot('image/gif'));
      expect((prepared.width, prepared.height), (30, 20));
      await expectLater(
        ImageImport.prepare(Uint8List.fromList(List.filled(64, 7))),
        throwsA(isA<ImageImportException>()),
      );
    });
  });

  group('ElementImages', () {
    test('mip levels are powers of two up to the natural width', () {
      expect(ElementImages.bucketFor(10, 4000), 64);
      expect(ElementImages.bucketFor(300, 4000), 512);
      expect(ElementImages.bucketFor(512, 4000), 512);
      expect(ElementImages.bucketFor(3000, 1000), 1000);
      expect(ElementImages.bucketFor(9000, 0), 4096);
      expect(ElementImages.bucketFor(40, 30), 30);
    });

    test('decodes asynchronously at the requested level, then serves it', () async {
      final blobs = {'p': pngOf(1000, 500)};
      final images = ElementImages(read: (sha) async => blobs[sha], fetch: (_) async => false);
      addTearDown(images.dispose);
      const data = ImageData(blob: 'p', width: 1000, height: 500);
      final changes = <String>[];
      images.changes.listen(changes.add);

      expect(images.imageFor(data, 200), isNull); // Not decoded yet.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final small = await images.load(data, 200);
      expect(small!.width, 256);
      expect(changes, ['p']);
      expect(images.imageFor(data, 200), same(small));

      // A sharper level: the smaller one stands in until it is ready.
      expect(images.imageFor(data, 900), same(small));
      final large = await images.load(data, 900);
      expect(large!.width, 1000);
      expect(images.imageFor(data, 100), same(small)); // Smallest ≥ 64 cached.
    });

    test('fetches missing blobs once and reports them when unavailable', () async {
      final fetched = <String>[];
      final stored = <String, Uint8List>{};
      final images = ElementImages(
        read: (sha) async => stored[sha],
        fetch: (sha) async {
          fetched.add(sha);
          if (sha == 'remote') stored[sha] = pngOf(10, 10);
          return stored.containsKey(sha);
        },
      );
      addTearDown(images.dispose);
      expect(
        await images.load(const ImageData(blob: 'remote', width: 10, height: 10), 10),
        isNotNull,
      );
      expect(await images.load(const ImageData(blob: 'gone', width: 10, height: 10), 10), isNull);
      expect(images.isMissing('gone'), isTrue);
      expect(images.isMissing('remote'), isFalse);
      images.imageFor(const ImageData(blob: 'gone', width: 10, height: 10), 10);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fetched, ['remote', 'gone']); // Not retried while missing.
      images.retryMissing();
      expect(images.isMissing('gone'), isFalse);
    });

    test('keeps decoded bitmaps within the memory budget', () async {
      final blobs = {for (var i = 0; i < 4; i++) 'b$i': pngOf(256, 256)};
      final images = ElementImages(
        read: (sha) async => blobs[sha],
        fetch: (_) async => false,
        budgetBytes: 256 * 256 * 4 * 2,
      );
      addTearDown(images.dispose);
      for (var i = 0; i < 4; i++) {
        await images.load(ImageData(blob: 'b$i', width: 256, height: 256), 256);
      }
      expect(images.bytes, lessThanOrEqualTo(256 * 256 * 4 * 2));
      expect(images.imageFor(const ImageData(blob: 'b3', width: 256, height: 256), 256), isNotNull);
    });
  });

  group('ImagePlacement', () {
    const area = Rect.fromLTWH(0, 0, 1000, 800);

    test('natural size when it fits, else 70 % of the view', () {
      const small = ImageData(blob: 'b', width: 200, height: 100);
      expect(
        ImagePlacement.boxFor(small, at: const Offset(500, 400), area: area),
        Rect.fromCenter(center: const Offset(500, 400), width: 200, height: 100),
      );
      const big = ImageData(blob: 'b', width: 4000, height: 3000);
      final box = ImagePlacement.boxFor(big, at: const Offset(500, 400), area: area);
      expect(box.width, closeTo(700, 1e-9));
      expect(box.height, closeTo(525, 1e-9));
    });

    test('stays on the page', () {
      const page = Rect.fromLTWH(0, 0, 600, 900);
      const data = ImageData(blob: 'b', width: 300, height: 300);
      final box = ImagePlacement.boxFor(data, at: const Offset(590, 10), area: area, page: page);
      expect(
        page.contains(box.topLeft) && page.contains(box.bottomRight - const Offset(1e-9, 1e-9)),
        isTrue,
      );
      expect(box.size, const Size(300, 300));
    });
  });

  group('on a surface', () {
    late AppDatabase db;
    late FakeClock clock;
    late SurfaceModel model;

    setUp(() {
      db = AppDatabase.inMemory();
      clock = FakeClock();
      model = SurfaceModel(
        surfaceId: 's',
        repository: StrokeRepository(db, deviceId: 'd', clock: clock),
        elementRepository: ElementRepository(db, deviceId: 'd', clock: clock),
        clock: clock,
      )..ensureLoaded(const Rect.fromLTWH(0, 0, 1000, 1000));
    });

    tearDown(() {
      model.dispose();
      db.close();
    });

    test('placing an image is one undoable edit, beneath the ink', () {
      final e = ImagePlacement.insert(
        model,
        const ImageData(blob: 'b', width: 10, height: 10),
        const Rect.fromLTWH(0, 0, 10, 10),
        id: 'img',
        now: 5,
      );
      expect(e.belowInk, isTrue);
      expect(model.elementById('img'), same(e));
      model.undo();
      expect(model.elementById('img'), isNull);
    });

    test('crop keeps the visible part in place, also when rotated', () {
      for (final rotation in [0.0, math.pi / 2, 0.7]) {
        final original = imageElement(
          'img',
          const Rect.fromLTWH(100, 100, 400, 200),
          rotation: rotation,
        );
        model.commit(InkEdit(addedElements: [original]));
        final session = ImageCropSession(model: model, element: original);
        expect(model.isHidden('img'), isTrue);
        // Pull the left edge in by a quarter of the image.
        final leftMid = session.toWorld.apply(const Offset(200, 200));
        session.dragHandle(CropHandle.left, leftMid);
        final cropped = session.commit();
        expect(model.isHidden('img'), isFalse);
        final data = ImageData.fromJson(cropped.data);
        expect(data.crop.left, closeTo(0.25, 1e-9));
        expect(cropped.rect.width, closeTo(300, 1e-9));
        expect(cropped.rotation, rotation);
        // The image's right edge did not move on the surface.
        Offset rightMid(SurfaceElement e) =>
            SurfaceElement.rotatedCorners(e.rect, e.rotation)[1] * 0.5 +
            SurfaceElement.rotatedCorners(e.rect, e.rotation)[2] * 0.5;
        expect((rightMid(cropped) - rightMid(original)).distance, lessThan(1e-6));

        // Reopening shows the whole image again and can undo the crop.
        final again = ImageCropSession(model: model, element: cropped);
        expect(again.imageRect.width, closeTo(400, 1e-6));
        again.reset();
        final restored = again.commit();
        expect(ImageData.fromJson(restored.data).isCropped, isFalse);
        expect((restored.rect.center - original.rect.center).distance, lessThan(1e-6));
        model.undo();
        model.undo();
        expect(model.elementById('img'), same(original));
        model.undo();
        expect(model.elementById('img'), isNull);
      }
    });

    test('crop panning and handles stay inside the image', () {
      final original = imageElement('img', const Rect.fromLTWH(0, 0, 400, 200));
      model.commit(InkEdit(addedElements: [original]));
      final session = ImageCropSession(model: model, element: original);
      session.dragHandle(CropHandle.bottomRight, const Offset(200, 100));
      expect(session.crop, const Rect.fromLTWH(0, 0, 200, 100));
      session.pan(session.crop, const Offset(500, 500));
      expect(session.crop, const Rect.fromLTWH(200, 100, 200, 100));
      session.dragHandle(CropHandle.topLeft, const Offset(9999, 9999));
      expect(session.crop.width, greaterThanOrEqualTo(session.minExtent - 1e-9));
      session.cancel();
      expect(model.isHidden('img'), isFalse);
      expect(model.elementById('img'), same(original));
    });

    test('an undo under an open crop session ends it', () {
      final original = imageElement('img', const Rect.fromLTWH(0, 0, 400, 200));
      model.commit(InkEdit(addedElements: [original]));
      var abandoned = false;
      ImageCropSession(model: model, element: original).onAbandoned = () => abandoned = true;
      model.undo();
      expect(abandoned, isTrue);
      expect(model.isHidden('img'), isFalse);
    });

    test('lasso: images beneath the ink need their outline inside', () {
      final image = imageElement('img', const Rect.fromLTWH(0, 0, 400, 400));
      final small = Lasso(const [
        Offset(150, 150),
        Offset(250, 150),
        Offset(250, 250),
        Offset(150, 250),
      ]);
      expect(small.selectsElement(image), isFalse);
      expect(small.selectsElement(image.copyWith(z: 3)), isTrue); // Above the ink.
      final around = Lasso(const [
        Offset(-10, -10),
        Offset(410, -10),
        Offset(410, 410),
        Offset(-10, 410),
      ]);
      expect(around.selectsElement(image), isTrue);
    });

    test('selection: front, back and duplicate keep or change the layer', () {
      final image = imageElement('img', const Rect.fromLTWH(0, 0, 100, 100), z: -4);
      final text = imageElement('top', const Rect.fromLTWH(200, 0, 100, 100), z: 2);
      model.commit(
        InkEdit(addedElements: [image, text], added: [stroke('ink', const Offset(10, 10))]),
      );
      final selection = SelectionController(model: model, clipboard: InkClipboard(), clock: clock);
      addTearDown(selection.dispose);
      selection.select(const [], [image]);
      selection.bringToFront();
      expect(model.elementById('img')!.z, 3);
      expect(model.strokeById('ink'), isNotNull); // Strokes untouched.
      selection.sendToBack();
      expect(model.elementById('img')!.z, -1); // Beneath the ink and everything else.
      expect(model.elementById('img')!.belowInk, isTrue);
      selection.duplicate();
      final copy = selection.elements.single;
      expect(copy.id, isNot('img'));
      expect(copy.belowInk, isTrue);
      expect(copy.z, greaterThan(model.elementById('img')!.z));
      model.undo(); // duplicate
      model.undo(); // back
      model.undo(); // front
      expect(model.elementById('img')!.z, -4);
    });

    test('a single element is framed along its rotation', () {
      final image = imageElement('img', const Rect.fromLTWH(0, 0, 100, 50), rotation: 0.5);
      model.commit(InkEdit(addedElements: [image]));
      final selection = SelectionController(model: model, clipboard: InkClipboard(), clock: clock);
      addTearDown(selection.dispose);
      selection.select(const [], [image]);
      expect(selection.frame!.angle, 0.5);
      expect(selection.frame!.rect, image.rect);
    });

    test('chunk pictures follow image decoding and zoom levels', () async {
      final blobs = {'p': pngOf(512, 512)};
      final images = ElementImages(read: (sha) async => blobs[sha], fetch: (_) async => false);
      addTearDown(images.dispose);
      final withImages = SurfaceModel(
        surfaceId: 's2',
        repository: StrokeRepository(db, deviceId: 'd', clock: clock),
        elementRepository: ElementRepository(db, deviceId: 'd', clock: clock),
        images: images,
        clock: clock,
      )..ensureLoaded(const Rect.fromLTWH(0, 0, 500, 500));
      addTearDown(withImages.dispose);
      withImages.commit(
        InkEdit(
          addedElements: [
            imageElement(
              'img',
              const Rect.fromLTWH(10, 10, 100, 100),
              blob: 'p',
              width: 512,
              height: 512,
            ),
          ],
        ),
      );
      final cache = ChunkPictureCache(withImages, devicePixelRatio: 1);
      addTearDown(cache.dispose);
      final invalidated = <Set<ChunkKey>?>[];
      withImages.invalidations.listen(invalidated.add);

      const key = (x: 0, y: 0);
      final placeholder = cache.pictureFor(key);
      expect(identical(cache.pictureFor(key), placeholder), isTrue);
      await images.load(const ImageData(blob: 'p', width: 512, height: 512), 100);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(invalidated, contains(equals({key}))); // Re-recorded with the bitmap.
      final sharp = cache.pictureFor(key);
      expect(identical(sharp, placeholder), isFalse);

      cache.setScale(1.2); // 2^0 → 2^1 pixels per unit: re-recorded.
      final zoomed = cache.pictureFor(key);
      expect(identical(zoomed, sharp), isFalse);
      cache.setScale(1.5); // Still 2^1.
      expect(identical(cache.pictureFor(key), zoomed), isTrue);
    });
  });
}
