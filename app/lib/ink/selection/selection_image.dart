import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../domain/image_data.dart';
import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../images/element_images.dart';
import '../render/content_painter.dart';

/// Where and how large [SelectionImage] draws a selection: the world
/// [area] it shows, at [scale] pixels per world unit, [width] × [height]
/// pixels.
typedef SelectionImageLayout = ({Rect area, double scale, int width, int height});

/// A picture of copied strokes and elements for other apps (the lasso's
/// Copy puts it on the system clipboard): the content alone, on a
/// transparent background, drawn like the canvas draws it.
abstract final class SelectionImage {
  /// Pixels per world unit (a page unit is 1/96 inch: about 290 dpi).
  static const double scale = 3;

  /// Longest side in pixels: a larger selection is drawn at a lower
  /// resolution.
  static const int maxPixels = 4096;

  /// Room around the content (world units), so antialiased edges aren't
  /// clipped.
  static const double margin = 2;

  /// The layout for content within world [bounds] (null if they are not
  /// finite).
  static SelectionImageLayout? layoutFor(Rect bounds) {
    if (!bounds.isFinite) return null;
    final area = bounds.inflate(margin);
    final fitted = math.min(scale, maxPixels / math.max(area.width, area.height));
    return (
      area: area,
      scale: fitted,
      width: math.max(1, (area.width * fitted).ceil()),
      height: math.max(1, (area.height * fitted).ceil()),
    );
  }

  /// World bounds of what [ContentPainter] draws of [strokes] and
  /// [elements] (links are not drawn); null if that is nothing.
  static Rect? drawnBounds(List<Stroke> strokes, List<SurfaceElement> elements) {
    Rect? r;
    for (final s in strokes) {
      final b = Stroke.computeBounds(s.points, s.width / 2);
      r = r == null ? b : r.expandToInclude(b);
    }
    for (final e in elements) {
      if (!_drawn(e)) continue;
      r = r == null ? e.bounds : r.expandToInclude(e.bounds);
    }
    return r;
  }

  static bool _drawn(SurfaceElement e) =>
      e.knownType == ElementType.text || e.knownType == ElementType.image;

  /// Draws [strokes] and [elements] into an image ([layoutFor] their
  /// [drawnBounds]), decoding their images from [images] first; null if
  /// nothing would be drawn.
  static Future<Image?> render(
    List<Stroke> strokes,
    List<SurfaceElement> elements, {
    ElementImages? images,
  }) async {
    final bounds = drawnBounds(strokes, elements);
    final layout = bounds == null ? null : layoutFor(bounds);
    if (layout == null) return null;
    if (images != null) {
      for (final e in elements.where((e) => e.knownType == ElementType.image)) {
        final data = ImageData.fromJson(e.data);
        await images.load(data, e.rect.width * layout.scale / data.crop.width);
      }
    }
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(layout.scale)
      ..translate(-layout.area.left, -layout.area.top);
    ContentPainter.paint(canvas, strokes, elements, images: images, pixelScale: layout.scale);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(layout.width, layout.height);
    } finally {
      picture.dispose();
    }
  }

  /// [render] encoded as PNG.
  static Future<Uint8List?> png(
    List<Stroke> strokes,
    List<SurfaceElement> elements, {
    ElementImages? images,
  }) async {
    final image = await render(strokes, elements, images: images);
    if (image == null) return null;
    try {
      final data = await image.toByteData(format: ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
