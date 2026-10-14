import 'dart:ui';

import '../../../domain/notebook_page.dart';
import '../../../domain/stroke.dart';
import 'pdf_page_info.dart';

/// The clean highlights over PDF text that a selection's Highlight and the
/// text-aware highlighter ([PdfHighlightSnap]) make: one straight
/// highlighter stroke per line, a little taller than its letters.
abstract final class PdfHighlights {
  /// A highlight's height relative to its line of text.
  static const double height = 1.1;

  /// A highlighter stroke over [line] of [page]; null for an empty line.
  static Stroke? stroke(
    PdfTextLine line,
    NotebookPage page, {
    required String id,
    required int color,
    required StrokeStyle style,
    required int createdAt,
  }) {
    final points = PdfHighlights.points(line.rect, page.size, direction: line.direction);
    if (points == null) return null;
    final across = line.thickness * (line.direction.vertical ? page.width : page.height);
    return Stroke(
      id: id,
      surfaceId: page.id,
      tool: InkTool.highlighter,
      color: color,
      width: (across * height).clamp(2.0, 200.0),
      // Flat ends, whatever the highlighter's: the band ends where the text
      // does (round caps would run past it).
      style: style.copyWith(ends: StrokeEnds.flat, taperStart: 0, taperEnd: 0),
      points: points,
      createdAt: createdAt,
    );
  }

  /// The points of a highlighter stroke across line [normalized] of a page
  /// of [size] units: along its middle in reading [direction], end to end
  /// (its flat ends add nothing), one point every 2 units.
  static List<StrokePoint>? points(
    Rect normalized,
    Size size, {
    PdfTextDirection direction = PdfTextDirection.ltr,
  }) {
    final r = Rect.fromLTRB(
      normalized.left * size.width,
      normalized.top * size.height,
      normalized.right * size.width,
      normalized.bottom * size.height,
    );
    if (r.width <= 0 || r.height <= 0) return null;
    final (from, to) = switch (direction) {
      PdfTextDirection.ltr => (r.centerLeft, r.centerRight),
      PdfTextDirection.rtl => (r.centerRight, r.centerLeft),
      PdfTextDirection.ttb => (r.topCenter, r.bottomCenter),
      PdfTextDirection.btt => (r.bottomCenter, r.topCenter),
    };
    final n = ((to - from).distance / 2).ceil().clamp(1, 2000);
    return [
      for (var i = 0; i <= n; i++)
        if (Offset.lerp(from, to, i / n) case final p?) StrokePoint(p.dx, p.dy, 0.5),
    ];
  }
}
