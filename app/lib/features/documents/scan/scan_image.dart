import 'dart:typed_data';

/// A raster image: straight (non-premultiplied) RGBA, 4 bytes per pixel,
/// row major. Plain typed data, so it can cross to a worker isolate.
class RgbaImage {
  /// Wraps [pixels] (length `width * height * 4`).
  RgbaImage(this.pixels, this.width, this.height) {
    if (pixels.length != width * height * 4) {
      throw ArgumentError.value(pixels.length, 'pixels', 'expected ${width * height * 4} bytes');
    }
  }

  /// A new image of [width] × [height] pixels, all transparent black.
  RgbaImage.blank(this.width, this.height) : pixels = Uint8List(width * height * 4);

  /// The pixel bytes.
  final Uint8List pixels;

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;
}
