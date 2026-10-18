import 'html_css.dart';
import 'text_data.dart';

/// One line of text read from HTML: its characters' styles, its
/// paragraph style, and hints read along the way.
class HtmlLine {
  final text = StringBuffer();
  final chars = <SpanStyle>[];
  ParaStyle? para;

  /// A checkbox `<input>` in it (checked or not).
  bool? check;

  /// The kind Word's list marker tells.
  ListKind? wordKind;

  bool get isEmpty => chars.isEmpty;
}

/// A table cell read from HTML (`<td>` / `<th>`): its inline content and
/// how it sits in its row.
class HtmlCell extends HtmlLine {
  HtmlCell({required this.th, required this.span, required this.width});

  final bool th;

  /// Columns it spans (`colspan`, at least 1).
  final int span;

  /// Its `width` (CSS or attribute), if it gives one.
  final HtmlLength? width;
}

/// A row of an [HtmlTable] and whether it is in `<thead>`.
typedef _Row = ({List<HtmlCell> cells, bool head});

/// A table being read from HTML: its rows of cells, `<col>` widths, and
/// whether rows are inside `<thead>`. [lines] turns it into a text box's
/// table: one line per cell, row-major.
class HtmlTable {
  final _rows = <_Row>[];
  final _cols = <HtmlLength?>[];
  _Row? _row;

  /// Rows started now are in `<thead>`.
  bool head = false;

  /// The cell being read, if any.
  HtmlCell? cell;

  /// Starts a row (ending the one before).
  void startRow() {
    endRow();
    _row = (cells: <HtmlCell>[], head: head);
  }

  /// Ends the current row (rows without cells are dropped).
  void endRow() {
    cell = null;
    final row = _row;
    if (row != null && row.cells.isNotEmpty) _rows.add(row);
    _row = null;
  }

  /// Starts a cell of the element [tag] with [attrs] (and a row if none is
  /// open).
  void startCell(String tag, Map<String, String> attrs) {
    if (_row == null) startRow();
    final span = int.tryParse(attrs['colspan']?.trim() ?? '') ?? 1;
    cell = HtmlCell(
      th: tag == 'th',
      span: span.clamp(1, TableSpec.maxColumns),
      width: _width(attrs),
    );
    _row!.cells.add(cell!);
  }

  /// A `<col>` (or `<colgroup>` without cols) with [attrs].
  void col(Map<String, String> attrs) {
    final span = (int.tryParse(attrs['span']?.trim() ?? '') ?? 1).clamp(1, TableSpec.maxColumns);
    final w = _width(attrs);
    for (var i = 0; i < span; i++) {
      _cols.add(w);
    }
  }

  static HtmlLength? _width(Map<String, String> attrs) =>
      parseLength(parseCss(attrs['style'] ?? '')['width']) ?? parseLength(attrs['width']);

  /// The table's cell lines (none when it has no cells): the widest row's
  /// columns (at most [TableSpec.maxColumns]), a spanned cell followed by
  /// empty ones, short rows padded; a header when the first row is in
  /// `<thead>` or all `<th>`; `<th>` cells outside it bold.
  List<HtmlLine> lines() {
    endRow();
    if (_rows.isEmpty) return const [];
    var columns = 1;
    for (final r in _rows) {
      final n = r.cells.fold(0, (a, c) => a + c.span);
      if (n > columns) columns = n;
    }
    if (columns > TableSpec.maxColumns) columns = TableSpec.maxColumns;
    final first = _rows.first;
    final header = first.head || first.cells.every((c) => c.th);
    final spec = TableSpec(_shares(columns), header: header);
    final out = <HtmlLine>[];
    for (final (r, row) in _rows.indexed) {
      final start = out.length;
      for (final c in row.cells) {
        if (out.length - start >= columns) break;
        out.add(_trimmed(c, bold: c.th && !(header && r == 0)));
        for (var k = 1; k < c.span && out.length - start < columns; k++) {
          out.add(HtmlLine());
        }
      }
      while (out.length - start < columns) {
        out.add(HtmlLine());
      }
    }
    for (final (k, l) in out.indexed) {
      l.para = ParaStyle(cell: TextTableCell(spec, first: k == 0));
    }
    return out;
  }

  /// [c]'s text without spaces at its ends, [bold] if asked.
  static HtmlLine _trimmed(HtmlCell c, {required bool bold}) {
    final text = c.text.toString();
    var from = 0, to = text.length;
    while (from < to && text[from] == ' ') {
      from++;
    }
    while (to > from && text[to - 1] == ' ') {
      to--;
    }
    final line = HtmlLine()..text.write(text.substring(from, to));
    for (final s in c.chars.sublist(from, to)) {
      line.chars.add(bold ? s.copyWith(bold: true) : s);
    }
    return line;
  }

  /// Column widths: the first row's cells' (a spanning cell's shared by
  /// its columns), else the `<col>`s', missing ones the mean of the
  /// others; even when none is given or percentages mix with lengths.
  List<double> _shares(int columns) {
    final fromCells = <HtmlLength?>[];
    for (final c in _rows.first.cells) {
      final w = c.width;
      for (var k = 0; k < c.span; k++) {
        fromCells.add(w == null ? null : (value: w.value / c.span, percent: w.percent));
      }
    }
    final cells = _fit(fromCells, columns);
    final cols = _fit(_cols, columns);
    final pick = cells.every((w) => w != null) || cols.any((w) => w == null) ? cells : cols;
    final known = [for (final w in pick) ?w];
    if (known.isEmpty || known.any((w) => w.percent != known.first.percent)) {
      return List.filled(columns, 1);
    }
    final mean = known.fold(0.0, (a, w) => a + w.value) / known.length;
    return [for (final w in pick) w?.value ?? mean];
  }

  static List<HtmlLength?> _fit(List<HtmlLength?> widths, int columns) => [
    for (var i = 0; i < columns; i++) i < widths.length ? widths[i] : null,
  ];
}
