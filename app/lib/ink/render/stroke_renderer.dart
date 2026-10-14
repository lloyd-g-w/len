import 'dart:ui';

import '../../domain/stroke.dart';
import 'outline_sink.dart';
import 'stroke_outline.dart';

/// Turns stroke points into filled outline paths and paints them.
///
/// Outlines come from [StrokeOutline]; the stroke's tool, width and
/// [StrokeStyle] decide their shape. Committed strokes are immutable, so
/// their paths are memoised per [Stroke] instance (and garbage-collected
/// with it).
abstract final class StrokeRenderer {
  static final Expando<Path> _paths = Expando('stroke paths');
  static final Expando<Path> _fills = Expando('stroke fills');

  /// The cached outline path of a committed stroke.
  static Path pathOf(Stroke stroke) => _paths[stroke] ??= buildPath(
    stroke.points,
    width: stroke.width,
    style: stroke.style,
    complete: true,
  );

  /// Caches [path] as the outline of the just-committed [stroke] (the live
  /// stroke's builder completes it at pen-up, see `LiveStrokeBuilder`), so
  /// committing does not rebuild it from scratch.
  static void adopt(Stroke stroke, Path path) => _paths[stroke] = path;

  /// Whether [stroke]'s outline is memoised already.
  static bool hasPath(Stroke stroke) => _paths[stroke] != null;

  /// Builds an outline path. [complete] is false while the stroke is still
  /// being drawn (its moving end is not trimmed).
  static Path buildPath(
    List<StrokePoint> points, {
    required double width,
    required StrokeStyle style,
    required bool complete,
  }) {
    final path = Path();
    emitOutline(PathSink(path), points, width: width, style: style, complete: complete);
    return path;
  }

  /// Like [buildPath], but writes the outline's segments to [sink] (tests
  /// and the Ink Lab measure them).
  static void emitOutline(
    OutlineSink sink,
    List<StrokePoint> points, {
    required double width,
    required StrokeStyle style,
    required bool complete,
  }) {
    if (points.isEmpty) return;
    StrokeOutline.emit(sink, points, specFor(width, style), complete: complete);
  }

  /// The outline shape parameters for a stroke: pen and highlighter alike,
  /// from its style ([StrokeStyle.ends] included).
  static OutlineSpec specFor(double width, StrokeStyle style) {
    final tapered = style.ends == StrokeEnds.tapered;
    return OutlineSpec(
      width: width,
      thinning: style.thinning,
      streamline: style.streamline,
      flatCaps: style.ends == StrokeEnds.flat,
      unit: style.unit,
      taperStart: tapered ? style.taperStart * width : 0,
      taperEnd: tapered ? style.taperEnd * width : 0,
      startPhase: style.startPhase,
      cutEnd: style.cutEnd,
    );
  }

  /// The fill paint for ink in colour [argb] with [style].
  static Paint paintFor(int argb, StrokeStyle style) {
    final color = Color(argb);
    return Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: color.a * style.opacity);
  }

  /// The area a filled shape's fill covers ([Stroke.fill]): the polygon
  /// of its points, memoised like [pathOf].
  static Path fillPathOf(Stroke stroke) => _fills[stroke] ??= fillPath(stroke.points);

  /// The polygon through [points] (a closed shape's fill).
  static Path fillPath(List<StrokePoint> points) => Path()
    ..fillType = PathFillType.nonZero
    ..addPolygon([for (final p in points) p.offset], true);

  /// The paint of fill colour [argb] (its alpha is the fill's opacity).
  static Paint fillPaint(int argb) => Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill
    ..color = Color(argb);

  /// Paints [stroke]'s fill, if it has one, beneath where its outline goes.
  static void drawFill(Canvas canvas, Stroke stroke) {
    final fill = stroke.fill;
    if (fill != null) canvas.drawPath(fillPathOf(stroke), fillPaint(fill));
  }

  /// Paints committed [stroke] onto [canvas] (in world coordinates): its
  /// fill, then its outline.
  static void draw(Canvas canvas, Stroke stroke) {
    drawFill(canvas, stroke);
    canvas.drawPath(pathOf(stroke), paintFor(stroke.color, stroke.style));
  }

  /// Paints [stroke] as a plain line along its points, [stroke.width]
  /// wide, unless its outline is already built: for ink far too small to
  /// show its shape (a library preview), where building outlines would
  /// cost most of the time.
  static void drawSketch(Canvas canvas, Stroke stroke) {
    if (hasPath(stroke) || stroke.points.length < 2) return draw(canvas, stroke);
    drawFill(canvas, stroke);
    final points = stroke.points;
    final path = Path()..moveTo(points.first.x, points.first.y);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].x, points[i].y);
    }
    canvas.drawPath(
      path,
      paintFor(stroke.color, stroke.style)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }
}
