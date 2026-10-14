import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import '../domain/chunk_grid.dart';
import '../domain/stroke.dart';
import '../domain/stroke_chunks.dart';
import 'stroke_codec.dart';

/// A stroke as `StrokeRepository` stores it: the values of its row and the
/// chunks it is indexed in.
///
/// Pulled stroke records are turned into rows ahead of applying them
/// ([StrokeRow.fromRecord]; off the UI thread on native, see
/// `platform/pull_decoder.dart`), so applying one is just its statements.
/// Plain data, so it crosses isolates cheaply.
class StrokeRow {
  const StrokeRow({
    required this.id,
    required this.surfaceId,
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
    required this.createdAt,
    required this.style,
    required this.chunks,
  });

  /// The row of [stroke].
  factory StrokeRow.of(Stroke stroke) => StrokeRow(
    id: stroke.id,
    surfaceId: stroke.surfaceId,
    tool: stroke.tool.name,
    color: stroke.color,
    width: stroke.width,
    points: StrokeCodec.encode(stroke.points),
    createdAt: stroke.createdAt,
    style: jsonEncode(styleJson(stroke.style, stroke.shape)),
    chunks: StrokeChunks.of(stroke).toList(growable: false),
  );

  /// The `style` column and record field: [style], with a shape's
  /// [shape] under `sh`.
  static Map<String, Object?> styleJson(StrokeStyle style, ShapeGeometry? shape) => {
    ...style.toJson(),
    if (shape != null) 'sh': shape.toJson(),
  };

  /// The shape stored in a decoded `style` field, if any; throws
  /// [FormatException] when it is malformed.
  static ShapeGeometry? shapeOf(Object? style) => switch (style) {
    {'sh': final Object sh} => ShapeGeometry.fromJson(sh),
    _ => null,
  };

  /// The row of the live stroke record [id] with payload [data]; throws
  /// [FormatException] (or a [TypeError] / [ArgumentError] a value check
  /// missed) when the record is malformed or its geometry invalid.
  ///
  /// Most handwriting lies within one chunk with pressures in range: such a
  /// stroke is validated on its encoded points as they are, without
  /// building it (a first sync decodes millions).
  factory StrokeRow.fromRecord(String id, Map<String, Object?> data) {
    final (surfaceId, tool, color, width, points, createdAt) = (
      data['surfaceId'],
      data['tool'],
      data['color'],
      data['width'],
      data['points'],
      data['createdAt'],
    );
    if (surfaceId is String &&
        tool is String &&
        color is int &&
        width is num &&
        width.isFinite &&
        width > 0 &&
        width <= maxWidth &&
        points is String &&
        createdAt is int) {
      final bytes = base64Decode(points);
      if (_singleChunk(bytes, width.toDouble()) case final ChunkKey key) {
        return StrokeRow(
          id: id,
          surfaceId: surfaceId,
          tool: InkTool.parse(tool).name,
          color: color,
          width: width.toDouble(),
          points: bytes,
          createdAt: createdAt,
          style: jsonEncode(styleJson(StrokeStyle.fromJson(data['style']), shapeOf(data['style']))),
          chunks: [key],
        );
      }
    }
    return StrokeRow.of(strokeFromRecord(id, data));
  }

  /// The one chunk ink of [width] through the encoded points [bytes]
  /// touches, if they are valid, stored as decoding would store them (all
  /// pressures within 0–1), within [WorldLimits] and in a single chunk.
  static ChunkKey? _singleChunk(Uint8List bytes, double width) {
    if (bytes.isEmpty || bytes.length % 12 != 0) return null;
    final data = ByteData.sublistView(bytes);
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (var o = 0; o < bytes.length; o += 12) {
      final x = data.getFloat32(o, Endian.little);
      final y = data.getFloat32(o + 4, Endian.little);
      final p = data.getFloat32(o + 8, Endian.little);
      if (!x.isFinite || !y.isFinite || !(p >= 0 && p <= 1)) return null;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    final bounds = Rect.fromLTRB(minX - width, minY - width, maxX + width, maxY + width);
    if (!WorldLimits.accepts(bounds)) return null;
    final range = ChunkGrid.rangeFor(bounds);
    return range.count == 1 ? (x: range.minX, y: range.minY) : null;
  }

  /// Widest stroke accepted from sync (far above any pen's range). Guards
  /// against corrupt records whose bounds would index millions of chunks.
  static const double maxWidth = 1000;

  final String id;
  final String surfaceId;

  /// The tool's name.
  final String tool;
  final int color;
  final double width;

  /// The points, encoded by [StrokeCodec].
  final Uint8List points;
  final int createdAt;

  /// The style as JSON.
  final String style;
  final List<ChunkKey> chunks;

  /// Parses and validates the live stroke record [id] with payload [data].
  static Stroke strokeFromRecord(String id, Map<String, Object?> data) {
    final surfaceId = data['surfaceId'];
    final tool = data['tool'];
    final color = data['color'];
    final width = data['width'];
    final points = data['points'];
    final createdAt = data['createdAt'];
    if (surfaceId is! String ||
        tool is! String ||
        color is! int ||
        width is! num ||
        points is! String ||
        createdAt is! int) {
      throw FormatException('Malformed stroke $id');
    }
    final decoded = StrokeCodec.decode(base64Decode(points));
    if (decoded.isEmpty || !width.isFinite || width <= 0 || width > maxWidth) {
      throw FormatException('Invalid stroke geometry $id');
    }
    if (!WorldLimits.accepts(Stroke.computeBounds(decoded, width.toDouble()))) {
      throw FormatException('Stroke $id is out of bounds');
    }
    return Stroke(
      id: id,
      surfaceId: surfaceId,
      tool: InkTool.parse(tool),
      color: color,
      width: width.toDouble(),
      points: decoded,
      createdAt: createdAt,
      style: StrokeStyle.fromJson(data['style']),
      shape: shapeOf(data['style']),
    );
  }
}
