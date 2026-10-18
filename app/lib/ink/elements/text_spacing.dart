import 'package:flutter/painting.dart';

import '../../domain/text/text_data.dart';
import 'text_layout.dart';

/// Paragraph spacing ([TextData.spacing]) in a text box's layout. A box is
/// one paragraph to Flutter, so the space below each of its paragraphs but
/// the last is a placeholder as wide as nothing at the paragraph's end,
/// hung below the baseline as far as the line reached plus the gap: its
/// last line is then that much taller, below its text, while wrapping,
/// alignment, highlights and the lines above stay as they were. How far a
/// line reaches below its baseline is measured: the text is laid out once
/// without spacing first.
///
/// The placeholder sits where the caret rests at the paragraph's end (the
/// caret stays before it): inside the isolate of a paragraph running
/// against the box, after the marker of an empty list item.
abstract final class TextSpacing {
  /// [plan]'s inserts (made at [width] for [data], without spacing) with
  /// the spacing of [data] added; [plan]'s own when there is none.
  static List<TextInsert> insertsOf(TextData data, TextPlan plan, double width) {
    final gap = data.paragraphGap;
    final text = data.text;
    if (gap <= 0 || !text.contains('\n')) return plan.inserts;
    final layout = TextBoxLayout.planned(data, width, plan);
    final painter = layout.painter;
    final lines = painter.computeLineMetrics();
    final heights = <int, double>{};
    for (var e = text.indexOf('\n'); e >= 0; e = text.indexOf('\n', e + 1)) {
      final d = plan.offsets.charAt(e);
      final y = painter.getOffsetForCaret(TextPosition(offset: d), Rect.zero).dy;
      heights[e] = _descentAt(lines, y) + gap;
    }
    layout.dispose();
    final out = <TextInsert>[];
    var i = 0;
    final inserts = plan.inserts;
    for (final MapEntry(key: at, value: height) in heights.entries) {
      while (i < inserts.length && inserts[i].at < at) {
        out.add(inserts[i++]);
      }
      final piece = InsertPiece.spacing(height);
      if (i < inserts.length && inserts[i].at == at) {
        out.add(_with(inserts[i++], piece));
      } else {
        out.add(TextInsert(at, [piece], caret: 0, allowed: {0}));
      }
    }
    out.addAll(inserts.skip(i));
    return out;
  }

  /// [insert] with [piece] where its caret rests (the caret staying
  /// before it).
  static TextInsert _with(TextInsert insert, InsertPiece piece) {
    final k = insert.caret;
    return TextInsert(
      insert.at,
      [...insert.pieces.take(k), piece, ...insert.pieces.skip(k)],
      caret: k,
      allowed: {for (final a in insert.allowed) a <= k ? a : a + 1},
    );
  }

  /// How far below its baseline the line at [y] (a caret's top) reaches.
  static double _descentAt(List<LineMetrics> lines, double y) {
    var top = 0.0;
    for (final l in lines) {
      if (y < top + l.height - 0.01) return l.descent;
      top += l.height;
    }
    return lines.isEmpty ? 0 : lines.last.descent;
  }
}
