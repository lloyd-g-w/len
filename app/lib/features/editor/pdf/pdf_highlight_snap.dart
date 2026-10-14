import 'dart:math' as math;
import 'dart:ui';

import '../../../core/clock.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/stroke.dart';
import '../../../ink/input/highlight_snap.dart';
import '../document/document_controller.dart';
import 'pdf_highlights.dart';
import 'pdf_page_info.dart';
import 'pdf_page_info_cache.dart';
import 'pdf_text_selection.dart';

/// The text-aware highlighter: a highlighter stroke drawn along one or
/// more lines of a PDF page's text becomes the clean, line-high highlights
/// a selection's Highlight makes, over the words it covers. Anything else
/// (a circle, a margin note, a stroke between lines, an underline) stays
/// as drawn. Always on: it needs no hold.
class PdfHighlightSnap implements HighlightSnap {
  PdfHighlightSnap({required this.doc, required this.info, this.clock = const Clock()});

  final DocumentController doc;
  final PdfPageInfoCache info;
  final Clock clock;

  /// The share of the stroke's length that must lie along text lines.
  static const double minCover = 0.7;

  /// How far a point may stray across a line (its height ×) and still be
  /// on it.
  static const double slack = 0.35;

  /// A line counts when the stroke runs along it this far (its height ×).
  static const double minRun = 1.5;

  /// How far (its height ×) the stroke's middle may lie from a line's
  /// middle, on average, for it to count: an underline just below the
  /// letters doesn't. A stroke wider than twice that may stray by half its
  /// width (it still covers the line's middle).
  static const double centred = 0.35;

  @override
  List<Stroke>? snap(Stroke stroke) {
    final page = doc.pages.where((p) => p.id == stroke.surfaceId).firstOrNull;
    final bg = page?.pdf;
    final glyphs = bg == null ? null : info.glyphs(bg.blob, bg.pageIndex);
    if (page == null || glyphs == null) return null;
    return snapTo(stroke, page, glyphs, newId: clock.newId);
  }

  /// [snap] on [page], whose text is [glyphs].
  static List<Stroke>? snapTo(
    Stroke stroke,
    NotebookPage page,
    PdfGlyphs glyphs, {
    required String Function() newId,
  }) {
    if (stroke.points.length < 2) return null;
    final lines = [for (final l in glyphs.lines) _Line(l, page.size)];
    if (lines.isEmpty) return null;
    // Walk the stroke, giving each step to the line it runs on, if any.
    var total = 0.0;
    final runs = <_Line, _Run>{};
    for (var i = 1; i < stroke.points.length; i++) {
      final a = stroke.points[i - 1].offset, b = stroke.points[i].offset;
      final step = (b - a).distance;
      total += step;
      final mid = (a + b) / 2;
      _Line? best;
      var bestAcross = double.infinity;
      for (final line in lines) {
        final across = line.across(mid);
        if (across < bestAcross && line.holds(mid)) (best, bestAcross) = (line, across);
      }
      if (best == null) continue;
      final run = runs.putIfAbsent(best, _Run.new);
      run.length += step;
      run.across += step * bestAcross;
      run.add(best.along(a));
      run.add(best.along(b));
    }
    final kept = [
      for (final MapEntry(key: line, value: run) in runs.entries)
        if (run.to - run.from >= minRun * line.thickness &&
            run.across <= run.length * math.max(centred * line.thickness, stroke.width / 2))
          (line, run),
    ];
    final covered = kept.fold(0.0, (sum, e) => sum + e.$2.length);
    if (total == 0 || covered < minCover * total) return null;
    final style = stroke.style.copyWith(thinning: 0, streamline: 0, taperStart: 0, taperEnd: 0);
    return [
      for (final (line, run) in kept)
        if (_words(glyphs, line, run) case (final start, final end))
          for (final part in glyphs.linesFor(start, end))
            ?PdfHighlights.stroke(
              part,
              page,
              id: newId(),
              color: stroke.color,
              style: style,
              createdAt: stroke.createdAt,
            ),
    ];
  }

  /// The characters of [line] the [run] covers (their middles within it),
  /// widened to whole words where it covers at least half of one.
  static (int, int)? _words(PdfGlyphs glyphs, _Line line, _Run run) {
    final slop = 0.2 * line.thickness;
    int? start, end;
    for (var i = line.text.start; i < line.text.end; i++) {
      final box = glyphs.boxes[i];
      if (box.isEmpty) continue;
      final mid = line.along(line.toPage(box.center));
      if (mid < run.from - slop || mid > run.to + slop) continue;
      start ??= i;
      end = i + 1;
    }
    if (start == null || end == null) return null;
    // A word more than half covered is highlighted whole, a word less
    // than half covered not at all.
    final (ws, we) = glyphs.wordAt(start);
    start = 2 * (math.min(end, we) - start) >= we - ws ? ws : we;
    final (vs, ve) = glyphs.wordAt(end - 1);
    end = 2 * (end - math.max(start, vs)) >= ve - vs ? ve : vs;
    if (start >= end) return null;
    return (start, end);
  }
}

/// A line of text in page units.
class _Line {
  _Line(this.text, Size size)
    : rect = Rect.fromLTRB(
        text.rect.left * size.width,
        text.rect.top * size.height,
        text.rect.right * size.width,
        text.rect.bottom * size.height,
      ),
      _size = size;

  final PdfTextLine text;
  final Rect rect;
  final Size _size;

  bool get vertical => text.direction.vertical;
  double get thickness => vertical ? rect.width : rect.height;

  Offset toPage(Offset normalized) =>
      Offset(normalized.dx * _size.width, normalized.dy * _size.height);

  /// Where [p] is along the line (page units, left / top first).
  double along(Offset p) => vertical ? p.dy : p.dx;

  /// How far [p] is from the line's middle across it.
  double across(Offset p) =>
      vertical ? (p.dx - rect.center.dx).abs() : (p.dy - rect.center.dy).abs();

  /// Whether [p] lies on the line (within [PdfHighlightSnap.slack] across,
  /// half a line height beyond its ends).
  bool holds(Offset p) {
    final a = along(p), from = vertical ? rect.top : rect.left;
    final to = vertical ? rect.bottom : rect.right;
    return across(p) <= thickness * (0.5 + PdfHighlightSnap.slack) &&
        a >= from - thickness / 2 &&
        a <= to + thickness / 2;
  }
}

/// How far a stroke runs along one line.
class _Run {
  double length = 0;

  /// The sum of each step's distance from the line's middle × its length.
  double across = 0;
  double from = double.infinity, to = double.negativeInfinity;

  void add(double along) {
    from = math.min(from, along);
    to = math.max(to, along);
  }
}
