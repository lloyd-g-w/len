import 'dart:ui';

import '../../../domain/notebook_page.dart';
import '../../../domain/stroke.dart';
import '../../../ink/undo_history.dart';
import 'pdf_interaction.dart';
import 'pdf_page_info.dart';

/// Highlights over the selected PDF text: the selection menu's "Remove
/// highlight" takes them away (a tap on highlighted text selects the text,
/// so this is the quick way to undo a highlight later).
extension PdfHighlightRemoval on PdfInteraction {
  /// The highlighter strokes over the selected lines, per page id (pages
  /// without any left out).
  Map<String, List<Stroke>> get selectedHighlights {
    final found = <String, List<Stroke>>{};
    for (final span in selection.spans) {
      final model = doc.surfaces.surfaceOf(span.page.id).model;
      final hits = <String, Stroke>{};
      for (final line in span.lines) {
        final area = PdfHighlightCover.lineArea(line, span.page);
        for (final s in model.strokesNear(area)) {
          if (s.tool.isHighlighter && PdfHighlightCover.covers(s, area)) hits[s.id] = s;
        }
      }
      if (hits.isNotEmpty) found[span.page.id] = hits.values.toList();
    }
    return found;
  }

  /// Whether some of the selected text is highlighted.
  bool get selectionHighlighted => selectedHighlights.isNotEmpty;

  /// Removes the highlighter strokes over the selected lines (whole
  /// strokes), as one undo step across pages; clears the selection.
  /// Returns how many strokes went.
  int removeSelectedHighlights() {
    final found = selectedHighlights;
    var removed = 0;
    doc.surfaces.models.group(() {
      for (final MapEntry(key: pageId, value: strokes) in found.entries) {
        doc.surfaces.surfaceOf(pageId).model.commit(InkEdit(removed: strokes));
        removed += strokes.length;
      }
    });
    selection.clear();
    return removed;
  }
}

/// When a highlighter stroke counts as over a line of PDF text.
abstract final class PdfHighlightCover {
  /// The share of a line's thickness, at each side, that a stroke's path
  /// must stay off: a highlight of the next line doesn't count.
  static const double _margin = 0.15;

  /// The area of [line] of [page] (page units) a highlight's path crosses:
  /// its box without a margin across.
  static Rect lineArea(PdfTextLine line, NotebookPage page) {
    final r = line.rect;
    final box = Rect.fromLTRB(
      r.left * page.width,
      r.top * page.height,
      r.right * page.width,
      r.bottom * page.height,
    );
    final across = (line.direction.vertical ? box.width : box.height) * _margin;
    return line.direction.vertical
        ? Rect.fromLTRB(box.left + across, box.top, box.right - across, box.bottom)
        : Rect.fromLTRB(box.left, box.top + across, box.right, box.bottom - across);
  }

  /// Whether [stroke]'s path (its middle, not its width: a highlight ends
  /// at its words) runs through [area].
  static bool covers(Stroke stroke, Rect area) {
    if (!stroke.bounds.overlaps(area)) return false;
    final points = stroke.points;
    if (points.isEmpty) return false;
    var a = Offset(points.first.x, points.first.y);
    if (area.contains(a)) return true;
    for (final p in points.skip(1)) {
      final b = Offset(p.x, p.y);
      if (_crosses(a, b, area)) return true;
      a = b;
    }
    return false;
  }

  /// Whether segment [a]→[b] meets [r] (Liang–Barsky clipping).
  static bool _crosses(Offset a, Offset b, Rect r) {
    var t0 = 0.0, t1 = 1.0;
    final d = b - a;
    for (final (p, q) in [
      (-d.dx, a.dx - r.left),
      (d.dx, r.right - a.dx),
      (-d.dy, a.dy - r.top),
      (d.dy, r.bottom - a.dy),
    ]) {
      if (p == 0) {
        if (q < 0) return false;
        continue;
      }
      final t = q / p;
      if (p < 0) {
        if (t > t1) return false;
        if (t > t0) t0 = t;
      } else {
        if (t < t0) return false;
        if (t < t1) t1 = t;
      }
    }
    return true;
  }
}
