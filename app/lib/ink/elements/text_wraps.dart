import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../domain/text/text_data.dart';
import 'text_layout.dart';

/// One line of a paragraph wrapped on its own ([TextWraps.linesOf]).
typedef WrappedLine = ({
  /// Model offset of its first character.
  int start,

  /// How many whitespace characters end it (0 on a paragraph's last line,
  /// whose spaces count as text).
  int trailing,

  /// Width of its text without the [trailing] whitespace.
  double width,

  /// Width of the [trailing] whitespace.
  double spaces,
});

/// Wrapping paragraphs on their own: hanging indents of wrapped list items
/// and the lines of paragraphs running against the box's direction.
///
/// A text box is laid out as one paragraph (so the editing field, the
/// canvas and the PDF export share one layout), and a paragraph cannot
/// indent its wrapped lines, nor align or run some of its lines
/// differently. So such paragraphs are wrapped here on their own (list
/// items at the box width minus their marker column); the layout then
/// breaks them at exactly those offsets ([TextPlan]), puts a gap as wide as
/// the marker in front of each continuation line and pads the lines of the
/// other direction into place. Continuation lines thus start where the
/// item's text does, at every indent level.
abstract final class TextWraps {
  /// Measuring margin, so the joined layout never needs an extra break
  /// where the paragraph's own layout just fitted.
  static const double epsilon = 0.01;

  /// Model offsets where lines of [data] continue on a new line when the
  /// box is [width] wide; none for unbounded widths.
  static List<int> of(TextData data, double width) => TextPlan.of(data, width).wraps;

  /// The lines of the text [start, end) of one paragraph (formatted as
  /// [para], running in [direction]) wrapped at [width] (unbounded: one
  /// line). [measure] also measures them (else widths are 0).
  static List<WrappedLine> linesOf(
    TextData data,
    List<SpanStyle> chars,
    ParaStyle para,
    int start,
    int end, {
    required double width,
    required TextDirection direction,
    bool measure = false,
  }) {
    if (end <= start || (!width.isFinite && !measure)) {
      return [(start: start, trailing: 0, width: 0, spaces: 0)];
    }
    final runs = <InlineSpan>[];
    TextLayout.lineRuns(data, chars, para, start, end, runs);
    final painter = TextPainter(
      text: TextSpan(style: TextLayout.baseStyle(data), children: runs),
      textDirection: direction,
    );
    if (width.isFinite) {
      painter.layout(maxWidth: math.max(1, width - epsilon));
    } else {
      painter.layout();
    }
    final length = end - start;
    final starts = <int>[0];
    while (true) {
      final next = painter.getLineBoundary(TextPosition(offset: starts.last)).end;
      if (next <= starts.last || next >= length) break;
      starts.add(next);
    }
    final out = <WrappedLine>[];
    for (var k = 0; k < starts.length; k++) {
      final from = starts[k];
      final to = k + 1 < starts.length ? starts[k + 1] : length;
      var trailing = 0;
      if (k + 1 < starts.length) {
        while (trailing < to - from && _isSpace(data.text.codeUnitAt(start + to - 1 - trailing))) {
          trailing++;
        }
      }
      out.add((
        start: start + from,
        trailing: trailing,
        width: measure ? _extent(painter, from, to - trailing) : 0,
        spaces: measure && trailing > 0 ? _sum(painter, to - trailing, to) : 0,
      ));
    }
    painter.dispose();
    return out;
  }

  static bool _isSpace(int unit) => unit == 0x20 || unit == 0x09 || unit == 0xA0 || unit == 0x3000;

  static List<TextBox> _boxes(TextPainter p, int from, int to) => to <= from
      ? const []
      : p.getBoxesForSelection(TextSelection(baseOffset: from, extentOffset: to));

  /// Width from the leftmost to the rightmost box of [from, to).
  static double _extent(TextPainter p, int from, int to) {
    final boxes = _boxes(p, from, to);
    if (boxes.isEmpty) return 0;
    final left = boxes.map((b) => b.left).reduce(math.min);
    final right = boxes.map((b) => b.right).reduce(math.max);
    return right - left;
  }

  /// Summed width of the boxes of [from, to).
  static double _sum(TextPainter p, int from, int to) =>
      _boxes(p, from, to).fold(0.0, (sum, b) => sum + b.right - b.left);
}
