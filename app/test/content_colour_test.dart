import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/image_data.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/stroke_style.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/span_style.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/ink/elements/text_layout.dart';
import 'package:len/ink/images/element_images.dart';
import 'package:len/ink/images/image_pixel.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tools/content_colour.dart';
import 'package:len/ink/undo_history.dart';

/// A straight stroke from [a] to [b], [width] wide.
Stroke _line(
  String id,
  Offset a,
  Offset b, {
  int color = 0xFF1A2233,
  InkTool tool = InkTool.ballpoint,
  double width = 4,
  int createdAt = 1,
  StrokeStyle style = const StrokeStyle(),
}) => Stroke(
  id: id,
  surfaceId: 's',
  tool: tool,
  color: color,
  width: width,
  style: style,
  points: [StrokePoint(a.dx, a.dy, 0.5), StrokePoint(b.dx, b.dy, 0.5)],
  createdAt: createdAt,
);

/// A closed square outline around [r] filled with [fill].
Stroke _square(String id, Rect r, int fill, {int createdAt = 1, int color = 0xFF1C7ED6}) => Stroke(
  id: id,
  surfaceId: 's',
  tool: InkTool.ballpoint,
  color: color,
  width: 2,
  style: StrokeStyle(fill: fill),
  points: [
    for (final p in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft, r.topLeft])
      StrokePoint(p.dx, p.dy, 0.5),
  ],
  createdAt: createdAt,
);

SurfaceElement _element(
  String id,
  ElementType type,
  Rect rect,
  Map<String, Object?> data,
  double z,
) => SurfaceElement(
  id: id,
  surfaceId: 's',
  type: type.name,
  rect: rect,
  z: z,
  createdAt: 1,
  data: data,
);

/// A 2 × 1 PNG: opaque red on the left, fully transparent on the right.
Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
      .drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint()..color = const Color(0xFFE03131));
  final image = await recorder.endRecording().toImage(2, 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SurfaceModel model;

  setUp(() {
    db = AppDatabase.inMemory();
    model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
      elementRepository: ElementRepository(db, deviceId: 'd'),
    );
  });
  tearDown(() {
    model.dispose();
    db.close();
  });

  void add({List<Stroke> strokes = const [], List<SurfaceElement> elements = const []}) =>
      model.commit(InkEdit(added: strokes, addedElements: elements));

  Future<int?> at(Offset p, {ImagePixel? imagePixel}) =>
      ContentColour.at(model, p, tolerance: 1, imagePixel: imagePixel);

  test('nothing there: null (the caller falls back to the paper)', () async {
    add(strokes: [_line('a', const Offset(0, 0), const Offset(100, 0))]);
    expect(await at(const Offset(50, 40)), isNull);
  });

  test('a stroke gives its own colour, opaque, whatever its opacity', () async {
    add(
      strokes: [
        _line(
          'a',
          const Offset(0, 0),
          const Offset(100, 0),
          color: 0xFF2F9E44,
          style: const StrokeStyle(opacity: 0.5),
        ),
      ],
    );
    expect(await at(const Offset(50, 1)), 0xFF2F9E44);
  });

  test('the highlighter gives its own colour, not its translucent look', () async {
    add(
      strokes: [
        _line(
          'h',
          const Offset(0, 0),
          const Offset(100, 0),
          color: 0xFFFACC15,
          tool: InkTool.highlighter,
          width: 20,
          style: StrokeStyle.defaultsFor(InkTool.highlighter),
        ),
      ],
    );
    expect(await at(const Offset(50, 5)), 0xFFFACC15);
  });

  test('ink beats a highlighter made after it (highlights lie beneath the ink)', () async {
    add(
      strokes: [
        _line('ink', const Offset(50, -20), const Offset(50, 20), color: 0xFF1C4ED8),
        _line(
          'h',
          const Offset(0, 0),
          const Offset(100, 0),
          color: 0xFFFACC15,
          tool: InkTool.highlighter,
          width: 20,
          createdAt: 5,
          style: StrokeStyle.defaultsFor(InkTool.highlighter),
        ),
      ],
    );
    expect(await at(const Offset(50, 0)), 0xFF1C4ED8);
    expect(await at(const Offset(80, 0)), 0xFFFACC15);
  });

  test('the topmost stroke wins', () async {
    add(
      strokes: [
        _line('old', const Offset(0, 0), const Offset(100, 0), color: 0xFF000000),
        _line('new', const Offset(50, -20), const Offset(50, 20), color: 0xFFE03131, createdAt: 2),
      ],
    );
    expect(await at(const Offset(50, 0)), 0xFFE03131);
  });

  test('a solid fill gives the fill; its outline the ink', () async {
    add(strokes: [_square('sq', const Rect.fromLTWH(0, 0, 100, 100), 0xFFFFD43B)]);
    expect(await at(const Offset(50, 50)), 0xFFFFD43B);
    expect(await at(const Offset(0, 50)), 0xFF1C7ED6);
  });

  test('a tint is translucent: alone it stays so; ink beneath it shows its own colour', () async {
    const tint = 0x401C7ED6;
    add(
      strokes: [
        _line('ink', const Offset(50, 0), const Offset(50, 100), color: 0xFF000000),
        _square('sq', const Rect.fromLTWH(0, 0, 100, 100), tint, createdAt: 2),
      ],
    );
    expect(await at(const Offset(20, 50)), tint);
    // The ink line under the tint is hit first: ink shows through tints,
    // and its own colour is what a pick there wants.
    expect(await at(const Offset(50, 50)), 0xFF000000);
  });

  test('a tint over a solid fill blends over it', () async {
    const tint = 0x80FFFFFF;
    add(
      strokes: [
        _square('under', const Rect.fromLTWH(0, 0, 100, 100), 0xFF000000),
        _square('over', const Rect.fromLTWH(20, 20, 60, 60), tint, createdAt: 2),
      ],
    );
    final colour = await at(const Offset(50, 50));
    expect(colour, Color.alphaBlend(const Color(tint), const Color(0xFF000000)).toARGB32());
  });

  test('text gives the colour of the character under the point, nothing between lines', () async {
    final data = TextData.rich(
      text: 'AB',
      fontSize: 20,
      color: 0xFF111111,
      spans: [const StyledRange(1, 2, SpanStyle(color: 0xFFE03131))],
    );
    add(
      elements: [
        _element('t', ElementType.text, const Rect.fromLTWH(0, 0, 200, 60), data.toJson(), 1),
      ],
    );
    final layoutTop = await _firstGlyphCentre(model, 0);
    expect(await at(layoutTop), 0xFF111111);
    expect(await at(await _firstGlyphCentre(model, 1)), 0xFFE03131);
    expect(await at(const Offset(150, 10)), isNull, reason: 'past the end of the line');
  });

  test('text above the ink wins over ink under it', () async {
    final data = TextData.rich(text: 'A', fontSize: 20, color: 0xFF7048E8);
    add(
      strokes: [_line('ink', const Offset(0, 0), const Offset(100, 30), width: 40)],
      elements: [
        _element('t', ElementType.text, const Rect.fromLTWH(0, 0, 200, 60), data.toJson(), 1),
      ],
    );
    expect(await at(await _firstGlyphCentre(model, 0)), 0xFF7048E8);
  });

  test(
    'images give the pixel of the decoded image; transparent pixels show what is beneath',
    () async {
      final png = await _png();
      final images = ElementImages(read: (_) async => png, fetch: (_) async => false);
      addTearDown(images.dispose);
      final image = ImageData(blob: 'ab' * 32, width: 2, height: 1);
      add(
        strokes: [_line('ink', const Offset(150, 0), const Offset(150, 100), color: 0xFF2F9E44)],
        elements: [
          _element('i', ElementType.image, const Rect.fromLTWH(0, 0, 200, 100), image.toJson(), -1),
        ],
      );
      Future<int?> pixel(ImageData d, Offset uv, double w) => ImagePixels.read(images, d, uv, w);
      // The left half is red.
      expect(await at(const Offset(50, 50), imagePixel: pixel), 0xFFE03131);
      // The right half is transparent: the paper (null) shows; the ink
      // above the image (an image beneath the ink) wins where it runs.
      expect(await at(const Offset(180, 50), imagePixel: pixel), isNull);
      expect(await at(const Offset(150, 50), imagePixel: pixel), 0xFF2F9E44);
    },
  );

  test('cropped and rotated images map the point into the crop', () async {
    final png = await _png();
    final images = ElementImages(read: (_) async => png, fetch: (_) async => false);
    addTearDown(images.dispose);
    SurfaceElement image(String id, Rect at, {Rect? crop, double rotation = 0}) => SurfaceElement(
      id: id,
      surfaceId: 's',
      type: ElementType.image.name,
      rect: at,
      rotation: rotation,
      z: 1,
      createdAt: 1,
      data: ImageData(blob: 'cd' * 32, width: 2, height: 1, crop: crop).toJson(),
    );
    add(
      elements: [
        // Turned half a turn: the red half is on the right.
        image('turned', const Rect.fromLTWH(0, 0, 100, 50), rotation: math.pi),
        // Only the red half shows, stretched over the box.
        image('red', const Rect.fromLTWH(0, 100, 100, 50), crop: const Rect.fromLTWH(0, 0, 0.5, 1)),
      ],
    );
    Future<int?> pixel(ImageData d, Offset uv, double w) => ImagePixels.read(images, d, uv, w);
    expect(await at(const Offset(10, 25), imagePixel: pixel), isNull);
    expect(await at(const Offset(90, 25), imagePixel: pixel), 0xFFE03131);
    expect(await at(const Offset(90, 125), imagePixel: pixel), 0xFFE03131);
  });

  test('rgbaToArgb', () {
    expect(ImagePixels.rgbaToArgb(0x11223344), 0x44112233);
    expect(ImagePixels.rgbaToArgb(0xFF0000FF), 0xFFFF0000);
  });
}

/// The centre of glyph [index] of the single text box of [model], as laid
/// out (the test font's glyphs are filled squares).
Future<Offset> _firstGlyphCentre(SurfaceModel model, int index) async {
  final e = model.elementsNear(const Rect.fromLTWH(-1000, -1000, 2000, 2000)).single;
  final layout = TextLayout.layout(TextData.fromJson(e.data), e.rect.width);
  final box = layout.boxesOf(index, index + 1).single.toRect();
  layout.dispose();
  return e.rect.topLeft + box.center;
}
