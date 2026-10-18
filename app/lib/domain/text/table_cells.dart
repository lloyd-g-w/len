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
    final para = paras[line];
    return TextData.rich(
      text: text.substring(from, to),
      spans: [
        for (final s in spans)
          if (s.end > from && s.start < to)
            StyledRange(s.start.clamp(from, to) - from, s.end.clamp(from, to) - from, s.style),
      ],
      paras: [ParaStyle(bold: para.cell?.header ?? false)],
      font: font,
      fontSize: fontSize,
      color: color,
      align: align,
    );
  }
}
