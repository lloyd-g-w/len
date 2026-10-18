import 'package:flutter/painting.dart';

import '../../domain/image_data.dart';
import '../../domain/surface_element.dart';
import '../../domain/text/text_data.dart';
import '../fonts/text_fonts.dart';
import '../images/element_images.dart';
import 'text_layout.dart';

/// Paints surface elements in world coordinates.
///
/// Elements are immutable values, so the text layout of each is memoised
/// per instance (like stroke paths) and rebuilt only for a new value.
/// Images come from [ElementImages] at a resolution matching [pixelScale]
/// (device pixels per world unit); until a bitmap is decoded — or when its
/// blob is unavailable — a placeholder is drawn instead.
abstract final class ElementRenderer {
  /// Text layouts by element, with the [TextFonts.changes] they were made
  /// at (a user font loaded or removed since lays them out again).
  static final Expando<(int, TextBoxLayout)> _layouts = Expando('element layouts');

  static void draw(
    Canvas canvas,
    SurfaceElement element, {
    ElementImages? images,
    double pixelScale = 1,
  }) {
    switch (element.knownType) {
      case ElementType.text:
        _drawRotated(canvas, element, () => _drawText(canvas, element));
      case ElementType.image:
        _drawRotated(canvas, element, () => _drawImage(canvas, element, images, pixelScale));
      case ElementType.link || null:
        break; // Links are shown by the editor; unknown types are kept, not drawn.
    }
  }

  static void _drawRotated(Canvas canvas, SurfaceElement e, void Function() paint) {
    canvas.save();
    if (e.rotation != 0) {
      final c = e.rect.center;
      canvas
        ..translate(c.dx, c.dy)
        ..rotate(e.rotation)
        ..translate(-c.dx, -c.dy);
    }
    paint();
    canvas.restore();
  }

  static void _drawText(Canvas canvas, SurfaceElement e) {
    final fonts = TextFonts.changes.value;
    var cached = _layouts[e];
    if (cached == null || cached.$1 != fonts) {
      cached = _layouts[e] = (fonts, TextLayout.layout(TextData.fromJson(e.data), e.rect.width));
    }
    cached.$2.paint(canvas, e.rect.topLeft);
  }

  static final Paint _imagePaint = Paint()
    ..filterQuality = FilterQuality.medium
    ..isAntiAlias = true;

  /// Whether [draw] draws [element] at [pixelScale] the same every time:
  /// not an image whose bitmap is still decoding (or missing), drawn from a
  /// stand-in, nor text in a user font (which may be loaded later, or
  /// removed).
  static bool isSettled(SurfaceElement element, ElementImages? images, double pixelScale) {
    if (element.knownType == ElementType.text) return !TextFonts.usesUserFonts(element.data);
    if (element.knownType != ElementType.image) return true;
    final data = ImageData.fromJson(element.data);
    return images?.isSharp(data, _pixelWidth(element, data, pixelScale)) ?? false;
  }

  /// Width of the whole (uncropped) image of [e] as drawn, in device pixels.
  static double _pixelWidth(SurfaceElement e, ImageData data, double scale) =>
      e.rect.width * scale / data.crop.width;

  static void _drawImage(Canvas canvas, SurfaceElement e, ElementImages? images, double scale) {
    final data = ImageData.fromJson(e.data);
    final crop = data.crop;
    final image = images?.imageFor(data, _pixelWidth(e, data, scale));
    if (image == null) {
      paintImagePlaceholder(canvas, e.rect, missing: images?.isMissing(data.blob) ?? true);
      return;
    }
    final w = image.width.toDouble(), h = image.height.toDouble();
    final source = Rect.fromLTRB(crop.left * w, crop.top * h, crop.right * w, crop.bottom * h);
    canvas.drawImageRect(image, source, e.rect, _imagePaint);
  }

  /// A quiet stand-in for an image that is loading, or (when [missing])
  /// not available on this device: a tinted box with a picture glyph.
  static void paintImagePlaceholder(Canvas canvas, Rect rect, {bool missing = false}) {
    canvas.drawRect(rect, Paint()..color = const Color(0x14707A8A));
    final side = (rect.shortestSide * 0.3).clamp(0.0, 96.0);
    if (side < 4) return;
    final glyph = Rect.fromCenter(center: rect.center, width: side, height: side * 0.8);
    final line = Paint()
      ..color = Color(missing ? 0x66B42318 : 0x55707A8A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = side / 16
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawRRect(RRect.fromRectAndRadius(glyph, Radius.circular(side / 10)), line)
      ..drawPath(
        Path()
          ..moveTo(glyph.left + side * 0.12, glyph.bottom - side * 0.15)
          ..lineTo(glyph.left + side * 0.4, glyph.top + side * 0.38)
          ..lineTo(glyph.left + side * 0.6, glyph.top + side * 0.55)
          ..lineTo(glyph.left + side * 0.72, glyph.top + side * 0.45)
          ..lineTo(glyph.right - side * 0.12, glyph.bottom - side * 0.15),
        line,
      )
      ..drawCircle(glyph.topRight + Offset(-side * 0.25, side * 0.22), side / 14, line);
    if (missing) {
      canvas.drawLine(glyph.topLeft, glyph.bottomRight, line);
    }
  }
}
