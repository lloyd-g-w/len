import 'dart:ui' as ui;

import '../../domain/image_data.dart';
import 'element_images.dart';

/// Reads single pixels of decoded images (the eyedropper's `ImagePixel`):
/// the pixel is copied into a 1 × 1 image and read back, so no whole
/// bitmap is ever copied out of the GPU.
abstract final class ImagePixels {
  /// The pixel at [uv] (normalised over the whole image) of [image] as
  /// [images] decodes it for drawing [pixelWidth] device pixels wide (ARGB,
  /// straight alpha); null if it cannot be decoded.
  static Future<int?> read(
    ElementImages images,
    ImageData image,
    ui.Offset uv,
    double pixelWidth,
  ) async {
    final bitmap = await images.load(image, pixelWidth);
    if (bitmap == null) return null;
    try {
      return await of(bitmap, uv);
    } catch (_) {
      return null; // Evicted (disposed) meanwhile.
    }
  }

  /// The pixel of [bitmap] at [uv] (normalised); null outside it.
  static Future<int?> of(ui.Image bitmap, ui.Offset uv) async {
    if (uv.dx < 0 || uv.dy < 0 || uv.dx > 1 || uv.dy > 1) return null;
    final x = (uv.dx * bitmap.width).floor().clamp(0, bitmap.width - 1);
    final y = (uv.dy * bitmap.height).floor().clamp(0, bitmap.height - 1);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      bitmap,
      ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
      const ui.Rect.fromLTWH(0, 0, 1, 1),
      ui.Paint()..blendMode = ui.BlendMode.src,
    );
    final picture = recorder.endRecording();
    final pixel = await picture.toImage(1, 1);
    picture.dispose();
    try {
      final bytes = await pixel.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (bytes == null) return null;
      return rgbaToArgb(bytes.getUint32(0));
    } finally {
      pixel.dispose();
    }
  }

  /// [rgba] (big-endian R, G, B, A bytes) as ARGB (no 32-bit shifts: web
  /// integers).
  static int rgbaToArgb(int rgba) => (rgba & 0xFF) * 0x1000000 + (rgba >>> 8);
}
