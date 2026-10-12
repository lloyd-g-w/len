import 'dart:math' as math;
import 'dart:ui';

import 'stroke_style.dart';

export 'stroke_style.dart';

/// Which tool produced a stroke: the pen ([ballpoint]) or the highlighter
/// (translucent, flat ends, drawn beneath other ink).
///
/// Stored by [name]; never rename a value.
enum InkTool {
  ballpoint,
  highlighter;

  bool get isHighlighter => this == highlighter;

  /// The tool named [value]; throws [FormatException] for unknown names
  /// (the stroke is malformed and skipped).
  static InkTool parse(String value) =>
      values.asNameMap()[value] ?? (throw FormatException('Unknown ink tool $value'));
}

/// A single sampled input point in world coordinates.
///
/// [pressure] is normalised to 0..1. Input devices without pressure report a
/// constant 0.5, which yields a uniform-width line.
class StrokePoint {
  const StrokePoint(this.x, this.y, this.pressure);

  final double x;
  final double y;
  final double pressure;

  Offset get offset => Offset(x, y);

  @override
  bool operator ==(Object other) =>
      other is StrokePoint && other.x == x && other.y == y && other.pressure == pressure;

  @override
  int get hashCode => Object.hash(x, y, pressure);

  @override
  String toString() => 'StrokePoint($x, $y, $pressure)';
}

/// An immutable, committed ink stroke.
///
/// Strokes are never edited after creation; they are only added or removed.
/// This keeps sync conflicts trivial and caches (paths, chunk pictures)
/// valid for the lifetime of the object.
class Stroke {
  Stroke({
    required this.id,
    required this.surfaceId,
    required this.tool,
    required this.color,
    required this.width,
    required List<StrokePoint> points,
    required this.createdAt,
    StrokeStyle? style,
  }) : assert(points.isNotEmpty, 'A stroke needs at least one point'),
       style = style ?? StrokeStyle.defaultsFor(tool),
       points = List.unmodifiable(points),
       bounds = computeBounds(points, width);

  final String id;

  /// The page id (paged notebooks) or notebook id (canvas) this stroke is on.
  final String surfaceId;

  final InkTool tool;

  /// ARGB colour.
  final int color;

  /// Nominal stroke diameter in world units.
  final double width;

  /// Rendering parameters (opacity, pressure response, stabiliser, tapers).
  final StrokeStyle style;

  final List<StrokePoint> points;

  /// When drawing the stroke began (pen down), in milliseconds since epoch;
  /// strokes are painted in this order and audio replay shows them from it.
  final int createdAt;

  /// Conservative world-space bounds including the stroke's thickness.
  final Rect bounds;

  /// The bounding box of [points] inflated by half the maximum line width.
  static Rect computeBounds(List<StrokePoint> points, double width) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in points) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }
    // Pressure can widen a stroke beyond its nominal width; pad generously.
    final pad = width;
    return Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
  }

  /// A stroke like this one but with other [points] (and optionally [id] /
  /// [style]); used to split strokes (pixel eraser) or straighten them.
  Stroke withPoints(List<StrokePoint> points, {String? id, StrokeStyle? style}) => Stroke(
    id: id ?? this.id,
    surfaceId: surfaceId,
    tool: tool,
    color: color,
    width: width,
    points: points,
    createdAt: createdAt,
    style: style ?? this.style,
  );

  /// Total paint order: creation time, then id for determinism across devices.
  static int paintOrder(Stroke a, Stroke b) {
    final byTime = a.createdAt.compareTo(b.createdAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }

  /// The order strokes are drawn in: highlighter ink underneath pen ink
  /// (like a real highlighter under printed text), each group in
  /// [paintOrder]. The single definition of ink layering: `ContentPainter`
  /// (chunk pictures, selections, thumbnails, PNG export) and PDF export use it.
  static int drawOrder(Stroke a, Stroke b) {
    final byLayer = (b.tool.isHighlighter ? 1 : 0) - (a.tool.isHighlighter ? 1 : 0);
    return byLayer != 0 ? byLayer : paintOrder(a, b);
  }
}
