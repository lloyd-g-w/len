import 'dart:typed_data';

import '../domain/stroke.dart';

/// Compact binary encoding of stroke points: little-endian float32
/// `x, y, pressure` triples (12 bytes per point).
abstract final class StrokeCodec {
  static const _stride = 12;

  static Uint8List encode(List<StrokePoint> points) {
    final data = ByteData(points.length * _stride);
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final o = i * _stride;
      data.setFloat32(o, p.x, Endian.little);
      data.setFloat32(o + 4, p.y, Endian.little);
      data.setFloat32(o + 8, p.pressure, Endian.little);
    }
    return data.buffer.asUint8List();
  }

  /// Decodes [bytes]; throws [FormatException] if the length is not a
  /// whole number of points or a value is not finite.
  static List<StrokePoint> decode(Uint8List bytes) {
    if (bytes.length % _stride != 0) {
      throw FormatException('Point data length ${bytes.length} is not a multiple of $_stride');
    }
    final data = ByteData.sublistView(bytes);
    final count = bytes.length ~/ _stride;
    return List.generate(count, (i) {
      final o = i * _stride;
      final x = data.getFloat32(o, Endian.little);
      final y = data.getFloat32(o + 4, Endian.little);
      final p = data.getFloat32(o + 8, Endian.little);
      if (!x.isFinite || !y.isFinite || !p.isFinite) {
        throw const FormatException('Non-finite point value');
      }
      return StrokePoint(x, y, p.clamp(0.0, 1.0));
    }, growable: false);
  }
}
