import 'text_data.dart';

/// The cells of a text box's tables as text of their own.
extension TableCells on TextData {
  /// The tables of the box, in line order.
  List<TextTable> get tables => TextTables.of(paras);

  /// The offset of each line's first character.
  List<int> get lineStarts {
    final starts = [0];
    for (var i = text.indexOf('\n'); i >= 0; i = text.indexOf('\n', i + 1)) {
      starts.add(i + 1);
    }
    return starts;
  }

  /// The cell on [line] as a box of its own (one line, the box's
  /// defaults, its character formatting; bold in a header row), starting
  /// at model offset [start] (see [lineStarts]).
  TextData cellData(int line, {int? start}) {
    final from = start ?? lineStarts[line];
    final nl = text.indexOf('\n', from);
    final to = nl < 0 ? text.length : nl;
    final para = paraOf(line);
    return TextData.rich(
      text: text.substring(from, to),
      spans: _spansIn(from, to),
      paras: [ParaStyle(bold: para.cell?.header ?? false)],
      font: font,
      fontSize: fontSize,
      color: color,
      align: align,
    );
  }

  /// The [spans] over [from, to), relative to [from].
  List<StyledRange> _spansIn(int from, int to) {
    final out = <StyledRange>[];
    for (var i = _firstSpanEndingAfter(from); i < spans.length; i++) {
      final s = spans[i];
      if (s.start >= to) break;
      out.add(StyledRange(s.start.clamp(from, to) - from, s.end.clamp(from, to) - from, s.style));
    }
    return out;
  }

  /// The first of the (ordered, disjoint) [spans] ending after [offset]: a
  /// big table's cells don't each look through every span of the box.
  int _firstSpanEndingAfter(int offset) {
    var lo = 0, hi = spans.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (spans[mid].end > offset) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }
}
