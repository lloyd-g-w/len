import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/clipboard/clipboard_mirror.dart';
import 'package:len/features/editor/clipboard/image_signature.dart';
import 'package:len/ink/images/element_images.dart';
import 'package:len/ink/selection/selection_image.dart';

/// Copy reaching other apps (UX_AUDIT R13-4): the picture of a selection,
/// recognising it again after the platform converted it, and the text of
/// copied text boxes.

Stroke _line(Offset from, Offset to, {int color = 0xFF1F2937, double width = 3}) => Stroke(
  id: 'ink',
  surfaceId: 's',
  tool: InkTool.ballpoint,
  color: color,
  width: width,
  points: [for (var i = 0; i <= 20; i++) _point(Offset.lerp(from, to, i / 20)!)],
  createdAt: 1,
);

SurfaceElement _box(String id, String text, Rect rect) => SurfaceElement(
  id: id,
  surfaceId: 's',
  type: ElementType.text.name,
  rect: rect,
  z: 1,
  createdAt: 1,
  data: TextData(text: text).toJson(),
);

SurfaceElement _link(Rect rect) => SurfaceElement(
  id: 'link',
  surfaceId: 's',
  type: ElementType.link.name,
  rect: rect,
  z: 1,
  createdAt: 1,
);

ElementImages _noImages() => ElementImages(read: (_) async => null, fetch: (_) async => false);

StrokePoint _point(Offset p) => StrokePoint(p.dx, p.dy, 0.5);

/// RGBA of pixel ([x], [y]) of PNG [bytes].
img.Pixel _pixel(Uint8List bytes, int x, int y) => img.decodePng(bytes)!.getPixel(x, y);

void main() {
  group('SelectionImage', () {
    test('frames the drawn content with a margin, at 3 px per unit', () {
      final stroke = _line(const Offset(100, 400), const Offset(200, 400));
      final bounds = SelectionImage.drawnBounds([stroke], const [])!;
      expect(bounds, const Rect.fromLTRB(98.5, 398.5, 201.5, 401.5));
      final layout = SelectionImage.layoutFor(bounds)!;
      expect(layout.area, bounds.inflate(SelectionImage.margin));
      expect(layout.scale, SelectionImage.scale);
      expect((layout.width, layout.height), (321, 21));
    });

    test('a large selection is drawn smaller, its longest side capped', () {
      final layout = SelectionImage.layoutFor(const Rect.fromLTWH(0, 0, 10000, 2000))!;
      expect(layout.width, SelectionImage.maxPixels);
      expect(layout.height, lessThan(SelectionImage.maxPixels ~/ 4));
      expect(layout.scale, lessThan(0.5));
    });

    test('links alone draw nothing; text boxes and ink are drawn', () {
      expect(
        SelectionImage.drawnBounds(const [], [_link(const Rect.fromLTWH(0, 0, 50, 20))]),
        isNull,
      );
      final box = _box('t', 'Hi', const Rect.fromLTWH(10, 20, 100, 30));
      expect(
        SelectionImage.drawnBounds(const [], [box, _link(const Rect.fromLTWH(500, 500, 9, 9))]),
        box.bounds,
      );
    });

    test('draws the ink in place on a transparent background', () async {
      final png = (await SelectionImage.png(
        [_line(const Offset(0, 0), const Offset(100, 100), color: 0xFFD03020, width: 6)],
        const [],
        images: _noImages(),
      ))!;
      final image = img.decodePng(png)!;
      final layout = SelectionImage.layoutFor(
        SelectionImage.drawnBounds([
          _line(const Offset(0, 0), const Offset(100, 100), width: 6),
        ], const [])!,
      )!;
      expect((image.width, image.height), (layout.width, layout.height));
      expect(image.numChannels, 4);
      // The middle of the diagonal is the ink's colour, opaque.
      final mid = _pixel(png, image.width ~/ 2, image.height ~/ 2);
      expect((mid.r, mid.g, mid.b, mid.a), (0xD0, 0x30, 0x20, 255));
      // Off the line: nothing (not paper).
      expect(_pixel(png, image.width - 4, 4).a, 0);
      expect(_pixel(png, 4, image.height - 4).a, 0);
    });

    test('draws text boxes', () async {
      final png = (await SelectionImage.png(const [], [
        _box('t', 'Hello there', const Rect.fromLTWH(0, 0, 200, 40)),
      ], images: _noImages()))!;
      final image = img.decodePng(png)!;
      var inked = 0;
      for (final p in image) {
        if (p.a > 128) inked++;
      }
      expect(inked, greaterThan(50));
      expect(inked, lessThan(image.width * image.height ~/ 2)); // No background.
    });
  });

  group('ImageSignature', () {
    Future<Uint8List> render(int color) async => (await SelectionImage.png(
      [
        _line(const Offset(0, 0), const Offset(120, 60), color: color, width: 8),
        _line(const Offset(0, 60), const Offset(120, 0), color: color, width: 8),
      ],
      const [],
      images: _noImages(),
    ))!;

    test('knows a picture again after re-encoding or flattening onto white', () async {
      final png = await render(0xFF1F2937);
      final mine = (await ImageSignature.of(png))!;
      final decoded = img.decodePng(png)!;
      // Linux / the web: re-encoded as PNG.
      final reencoded = (await ImageSignature.of(img.encodePng(decoded, level: 1)))!;
      expect(mine.matches(reencoded), isTrue);
      // Windows: a DIB without alpha, over white.
      final flat = img.Image(width: decoded.width, height: decoded.height)
        ..clear(img.ColorRgb8(255, 255, 255));
      img.compositeImage(flat, decoded);
      final bmp = (await ImageSignature.of(img.encodeBmp(flat)))!;
      expect(mine.matches(bmp), isTrue);
    });

    test('tells a recoloured, resized or other picture apart', () async {
      final mine = (await ImageSignature.of(await render(0xFF1F2937)))!;
      final red = (await ImageSignature.of(await render(0xFFD03020)))!;
      expect(mine.matches(red), isFalse);
      final decoded = img.decodePng(await render(0xFF1F2937))!;
      final smaller = img.copyResize(decoded, width: decoded.width - 2);
      expect(mine.matches((await ImageSignature.of(img.encodePng(smaller)))!), isFalse);
      final blank = img.Image(width: decoded.width, height: decoded.height, numChannels: 4);
      expect(mine.matches((await ImageSignature.of(img.encodePng(blank)))!), isFalse);
    });

    test('is null for bytes that are no image', () async {
      expect(await ImageSignature.of(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });

  group('ClipboardMirror', () {
    test('writes a picture of ink, no text; knows it again, converted or not', () async {
      Uint8List? written;
      String? sent = 'unset';
      final mirror = ClipboardMirror(
        images: _noImages(),
        write: ({png, text}) async {
          written = await png;
          sent = text;
          return true;
        },
      );
      final ok = await mirror.copy([
        _line(const Offset(0, 0), const Offset(80, 40), width: 6),
      ], const []);
      expect(ok, isTrue);
      expect(written, isNotNull);
      expect(sent, isNull);
      expect(await mirror.holdsInk(written!), isTrue);
      final reencoded = img.encodePng(img.decodePng(written!)!, level: 1);
      expect(await mirror.holdsInk(reencoded), isTrue);
      final other = img.encodePng(img.Image(width: 20, height: 20, numChannels: 4));
      expect(await mirror.holdsInk(other), isFalse);
      // A later copy replaces it.
      final first = written!;
      await mirror.copy([_line(const Offset(0, 0), const Offset(30, 90))], const []);
      expect(await mirror.holdsInk(first), isFalse);
      expect(await mirror.holdsInk(written!), isTrue);
    });

    test('text boxes alone also go as text, top to bottom', () async {
      String? sent;
      final mirror = ClipboardMirror(
        images: _noImages(),
        write: ({png, text}) async {
          await png;
          sent = text;
          return true;
        },
      );
      await mirror.copy(const [], [
        _box('b', 'Second', const Rect.fromLTWH(0, 100, 100, 30)),
        _box('a', 'First line\nand more  ', const Rect.fromLTWH(50, 0, 100, 30)),
      ]);
      expect(sent, 'First line\nand more\n\nSecond');
      expect(mirror.holdsInkText('First line\r\nand more\r\n\r\nSecond'), isTrue);
      expect(mirror.holdsInkText('Second'), isFalse);
      // With ink among them: the picture only.
      await mirror.copy(
        [_line(Offset.zero, const Offset(9, 9))],
        [_box('a', 'First', const Rect.fromLTWH(50, 0, 100, 30))],
      );
      expect(sent, isNull);
      expect(mirror.holdsInkText('First'), isFalse);
    });

    test('plain text needs text boxes only', () {
      final box = _box('a', 'Hi', const Rect.fromLTWH(0, 0, 10, 10));
      expect(ClipboardMirror.plainText([box]), 'Hi');
      expect(ClipboardMirror.plainText([box, _link(const Rect.fromLTWH(0, 0, 5, 5))]), isNull);
      expect(
        ClipboardMirror.plainText([_box('e', '  ', const Rect.fromLTWH(0, 0, 10, 10))]),
        isNull,
      );
      expect(ClipboardMirror.plainText(const []), isNull);
    });
  });
}
