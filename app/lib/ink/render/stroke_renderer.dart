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

  /// The cached outline path of a committed stroke.
  static Path pathOf(Stroke stroke) => _paths[stroke] ??= buildPath(
    stroke.points,
    tool: stroke.tool,
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
    required InkTool tool,
    required double width,
    required StrokeStyle style,
    required bool complete,
  }) {
    final path = Path();
    emitOutline(PathSink(path), points, tool: tool, width: width, style: style, complete: complete);
    return path;
  }

  /// Like [buildPath], but writes the outline's segments to [sink] (tests
  /// and the Ink Lab measure them).
  static void emitOutline(
    OutlineSink sink,
    List<StrokePoint> points, {
    required InkTool tool,
    required double width,
    required StrokeStyle style,
    required bool complete,
  }) {
    if (points.isEmpty) return;
    StrokeOutline.emit(sink, points, specFor(tool, width, style), complete: complete);
  }

  /// The outline shape parameters for a stroke; the highlighter has flat
  /// ends, the pen round caps.
  static OutlineSpec specFor(InkTool tool, double width, StrokeStyle style) => OutlineSpec(
    width: width,
    thinning: style.thinning,
    streamline: style.streamline,
    taperStart: style.taperStart,
    taperEnd: style.taperEnd,
    flatCaps: tool.isHighlighter,
    unit: style.unit,
  );

  /// The fill paint for ink in colour [argb] with [style].
  static Paint paintFor(int argb, StrokeStyle style) {
    final color = Color(argb);
    return Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: color.a * style.opacity);
  }

  /// Paints committed [stroke] onto [canvas] (in world coordinates).
  static void draw(Canvas canvas, Stroke stroke) =>
      canvas.drawPath(pathOf(stroke), paintFor(stroke.color, stroke.style));

  /// Paints [stroke] as a plain line along its points, [stroke.width]
  /// wide, unless its outline is already built: for ink far too small to
  /// show its shape (a library preview), where building outlines would
  /// cost most of the time.
  static void drawSketch(Canvas canvas, Stroke stroke) {
    if (hasPath(stroke) || stroke.points.length < 2) return draw(canvas, stroke);
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
