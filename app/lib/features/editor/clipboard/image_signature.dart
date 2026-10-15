import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A coarse look at an image, to recognise it after the system clipboard
/// converted it (re-encoded it, or — Windows' DIB — flattened it onto
/// white): its size and a [grid] × [grid] RGB thumbnail over white.
class ImageSignature {
  const ImageSignature(this.width, this.height, this.cells);

  /// Cells per side of the thumbnail.
  static const int grid = 16;

  /// Largest difference of a cell's channel still taken as the same image
  /// (conversions round; a recoloured or edited image differs by more).
  static const int tolerance = 12;

  final int width;
  final int height;

  /// [grid] × [grid] cells, R, G, B each, composited over white.
  final Uint8List cells;

  /// The signature of encoded image [bytes] (any format the engine
  /// decodes); null if they can't be decoded.
  static Future<ImageSignature?> of(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final (width, height) = (descriptor.width, descriptor.height);
      codec = await descriptor.instantiateCodec(targetWidth: grid, targetHeight: grid);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      frame.image.dispose();
      if (data == null) return null;
      final cells = Uint8List(grid * grid * 3);
      for (var i = 0; i < grid * grid; i++) {
        final alpha = data.getUint8(i * 4 + 3);
        for (var c = 0; c < 3; c++) {
          final value = data.getUint8(i * 4 + c);
          cells[i * 3 + c] = (value * alpha + 255 * (255 - alpha) + 127) ~/ 255;
        }
      }
      return ImageSignature(width, height, cells);
    } on Object {
      return null;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// Whether [other] shows the same picture (same size, cells within
  /// [tolerance]).
  bool matches(ImageSignature other) {
    if (width != other.width || height != other.height) return false;
    var worst = 0;
    for (var i = 0; i < cells.length; i++) {
      worst = math.max(worst, (cells[i] - other.cells[i]).abs());
    }
    return worst <= tolerance;
  }
}
