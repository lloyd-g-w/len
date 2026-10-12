import 'package:flutter/widgets.dart';

import '../../domain/text/text_data.dart';
import 'text_layout.dart';

/// Hanging indents of wrapped list items.
///
/// A text box is laid out as one paragraph (so the editing field, the
/// canvas and the PDF export share one layout), and a paragraph cannot
/// indent its wrapped lines. So each list item is wrapped here on its own,
/// at the box width minus its marker column; the layout then breaks the
/// item at exactly those offsets and puts a gap as wide as the marker in
/// front of each continuation line ([MarkerOffsets.wrapText],
/// [TextLayout.spanOf]). Continuation lines thus start where the item's
/// text does, at every indent level.
abstract final class TextWraps {
  /// Measuring margin, so the joined layout never needs an extra break
  /// where the item's own layout just fitted.
  static const double _epsilon = 0.01;

  /// Model offsets where wrapped list items of [data] continue on a new
  /// line when the box is [width] wide; none for unbounded widths.
  static List<int> of(TextData data, double width) {
    if (!width.isFinite) return const [];
    final w = width < TextLayout.minWidth ? TextLayout.minWidth : width;
    final markers = TextLayout.markersOf(data);
    if (markers.isEmpty) return const [];
    final chars = data.charStyles();
    final text = data.text;
    final out = <int>[];
    var line = 0;
    var start = 0;
    for (final m in markers) {
      while (line < m.line) {
        start = text.indexOf('\n', start) + 1;
        line++;
      }
      final nl = text.indexOf('\n', start);
      final end = nl < 0 ? text.length : nl;
      if (end > start) {
        final runs = <InlineSpan>[];
        TextLayout.lineRuns(data, chars, m.para, start, end, runs);
        final available = w - m.size.width - _epsilon;
        for (final at in _lineStarts(runs, TextLayout.baseStyle(data), available)) {
          out.add(start + at);
        }
      }
    }
    return out;
  }

  /// Offsets (in the runs' text) where its 2nd, 3rd, … line start when
  /// wrapped at [width].
  static List<int> _lineStarts(List<InlineSpan> runs, TextStyle base, double width) {
    final painter = TextPainter(
      text: TextSpan(style: base, children: runs),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width < 1 ? 1 : width);
    final out = <int>[];
    final lines = painter.computeLineMetrics();
    for (final l in lines.skip(1)) {
      final at = painter.getPositionForOffset(Offset(-1, l.baseline)).offset;
      if (at > 0 && (out.isEmpty || at > out.last)) out.add(at);
    }
    painter.dispose();
    return out;
  }
}
