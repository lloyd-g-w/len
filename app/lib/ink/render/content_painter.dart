import 'dart:ui';

import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../elements/element_renderer.dart';
import '../images/element_images.dart';
import 'stroke_renderer.dart';

/// Paints a surface's content in its layers, the same everywhere (chunk
/// pictures, selections, thumbnails, raster export):
///
/// 1. elements beneath the ink (`z < 0`: images by default),
/// 2. highlighter strokes (like a real highlighter under printed text),
/// 3. all other ink,
/// 4. elements above the ink (text, images brought to the front).
///
/// Within each layer strokes keep their paint order and elements their
/// stacking order. Changing how content looks? Bump `StoredRasters.format`,
/// or canvases zoomed far out keep showing rasters drawn before.
///
/// With `sketchThin`, strokes narrower than `sketchBelow` pixels (at
/// `pixelScale` pixels per unit) are drawn as plain lines
/// ([StrokeRenderer.drawSketch]): previews of a page or a canvas need no
/// outlines for ink that thin.
abstract final class ContentPainter {
  /// Pixel width under which `sketchThin` draws strokes as plain lines, by
  /// default.
  static const double hairline = 1.5;

  static void paint(
    Canvas canvas,
    Iterable<Stroke> strokes,
    Iterable<SurfaceElement> elements, {
    ElementImages? images,
    double pixelScale = 1,
    bool sketchThin = false,
    double sketchBelow = hairline,
  }) {
    final ink = strokes.toList()..sort(Stroke.drawOrder);
    final items = elements.toList()..sort(SurfaceElement.paintOrder);
    void drawElements(bool belowInk) {
      for (final e in items) {
        if (e.belowInk == belowInk) {
          ElementRenderer.draw(canvas, e, images: images, pixelScale: pixelScale);
        }
      }
    }

    drawElements(true);
    for (final s in ink) {
      if (sketchThin && s.width * pixelScale < sketchBelow) {
        StrokeRenderer.drawSketch(canvas, s);
      } else {
        StrokeRenderer.draw(canvas, s);
      }
    }
    drawElements(false);
  }
}
