import 'dart:ui';

import '../../domain/image_data.dart';
import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../../domain/text/text_data.dart';
import '../elements/text_hit_test.dart';
import '../elements/text_layout.dart';
import '../stroke_hit_test.dart';
import '../surface_model.dart';

/// Reads the pixel of [image] at [uv] (normalised over the whole, uncropped
/// image), decoded for drawing about [pixelWidth] device pixels wide, as
/// ARGB; null when no bitmap is available.
typedef ImagePixel = Future<int?> Function(ImageData image, Offset uv, double pixelWidth);

/// The colour a surface's content shows at a point, for the eyedropper:
/// the content's own colour rather than its rendered pixels.
///
/// Items are visited top down in the order `ContentPainter` paints them
/// (elements above the ink, ink, highlighter, elements beneath the ink):
///
/// - a stroke's line gives the stroke's colour, opaque: a pen's opacity and
///   a highlighter's translucency belong to the tool, not the colour (a
///   highlighter's colour picked again draws the same highlight);
/// - a closed shape's solid fill gives the fill colour; a tint is
///   translucent and blends over what lies beneath it;
/// - a text box gives the colour of the character under the point (none
///   between the lines);
/// - an image gives its pixel ([ImagePixel]); transparent pixels let what
///   lies beneath show through.
///
/// The first opaque colour ends the search. The result may be translucent
/// (tints over bare paper): the caller blends it over the background.
abstract final class ContentColour {
  /// The colour at [world] (surface units) of [model]'s content; null over
  /// nothing. [tolerance] (surface units) widens strokes' lines; [pixelScale]
  /// is device pixels per unit (for image decodes).
  static Future<int?> at(
    SurfaceModel model,
    Offset world, {
    required double tolerance,
    double pixelScale = 1,
    ImagePixel? imagePixel,
  }) async {
    final elements =
        model
            .elementsNear(Rect.fromCircle(center: world, radius: 1))
            .where((e) => e.contains(world))
            .toList()
          ..sort(SurfaceElement.paintOrder);
    final strokes =
        model
            .strokesNear(Rect.fromCircle(center: world, radius: tolerance))
            .where((s) => StrokeHitTest.sweepHits(s, world, world, tolerance))
            .toList()
          ..sort(Stroke.drawOrder);
    final layers = <int>[];
    Future<bool> visitElements(bool belowInk) async {
      for (final e in elements.reversed) {
        if (e.belowInk != belowInk) continue;
        final colour = switch (e.knownType) {
          ElementType.text => textColourAt(e, world),
          ElementType.image => await _imageColourAt(e, world, pixelScale, imagePixel),
          _ => null,
        };
        if (colour != null && _add(layers, colour)) return true;
      }
      return false;
    }

    final opaque =
        await visitElements(false) ||
        strokes.reversed.any((s) => _add(layers, strokeColourAt(s, world, tolerance))) ||
        await visitElements(true);
    if (layers.isEmpty) return null;
    // Blend bottom up; without an opaque base the result stays translucent.
    var colour = opaque ? layers.last : 0x00000000;
    for (final top in layers.reversed.skip(opaque ? 1 : 0)) {
      colour = Color.alphaBlend(Color(top), Color(colour)).toARGB32();
    }
    return colour;
  }

  /// Adds [colour] to [layers]; true once it is opaque (nothing beneath
  /// shows through).
  static bool _add(List<int> layers, int? colour) {
    if (colour == null || colour >>> 24 == 0) return false;
    layers.add(colour);
    return colour >>> 24 == 0xFF;
  }

  /// The colour [stroke] shows at [world]: its line's (opaque), else its
  /// fill's; null when neither is there.
  static int? strokeColourAt(Stroke stroke, Offset world, double tolerance) {
    if (StrokeHitTest.sweepHits(stroke, world, world, tolerance, fill: false)) {
      return stroke.color | 0xFF000000;
    }
    return StrokeHitTest.fillContains(stroke, world) ? stroke.fill : null;
  }

  /// The colour of the character of text box [element] under [world]; null
  /// between characters and lines.
  static int? textColourAt(SurfaceElement element, Offset world) {
    final data = TextData.fromJson(element.data);
    if (data.text.isEmpty) return null;
    final local = TextHitTest.toLocal(element, world);
    final layout = TextLayout.layout(data, element.rect.width);
    try {
      final display = layout.painter.getPositionForOffset(local).offset;
      final offsets = layout.offsets;
      for (final m in {offsets.toModel(display), offsets.toModel(display) - 1}) {
        if (m < 0 || m >= data.text.length || data.text[m] == '\n') continue;
        final boxes = layout.boxesOf(m, m + 1);
        if (!boxes.any((b) => b.toRect().contains(local))) continue;
        return data.charStyles()[m].color ?? data.color;
      }
      return null;
    } finally {
      layout.dispose();
    }
  }

  static Future<int?> _imageColourAt(
    SurfaceElement element,
    Offset world,
    double pixelScale,
    ImagePixel? imagePixel,
  ) async {
    if (imagePixel == null) return null;
    final data = ImageData.fromJson(element.data);
    final rect = element.rect;
    if (rect.isEmpty) return null;
    final local = TextHitTest.toLocal(element, world);
    final crop = data.crop;
    final uv = Offset(
      crop.left + local.dx / rect.width * crop.width,
      crop.top + local.dy / rect.height * crop.height,
    );
    return imagePixel(data, uv, rect.width * pixelScale / crop.width);
  }
}
