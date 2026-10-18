import 'rich_text_buffer.dart';
import 'text_data.dart';

/// Editing the tables of a text box's [RichTextBuffer] (see [TextTable]):
/// inserting and removing tables, rows and columns, widths and the header,
/// a cell's text, and repairing what other edits leave of a table. Rows
/// and columns are counted from 0; lines are the buffer's.
extension TableEdits on RichTextBuffer {
  /// The tables, in line order.
  List<TextTable> get tables => TextTables.of(paras);

  /// The table holding [line], if any.
  TextTable? tableAt(int line) => TextTables.at(tables, line);

  /// Inserts a table of [rows] × [columns] empty cells at [offset] (not in
  /// a table): in place of an empty line, else above the line when
  /// [offset] is at its start, below it at its end, or splitting it. A line
  /// always follows the table. Returns the table.
  TextTable insertTable(int offset, int rows, int columns, {bool header = false}) {
    final line = lineOf(offset);
    final spec = TableSpec.even(columns, header: header);
    final cells = _cells(spec, rows * spec.columns);
    final l = lineAt(line);
    final at = offset - lineStart(line);
    final List<BufferLine> lines;
    final int first;
    if (l.text.isEmpty) {
      lines = [...cells, _empty(l.para)];
      first = line;
    } else if (at == 0) {
      lines = [...cells, l];
      first = line;
    } else {
      final rest = (text: l.text.substring(at), chars: l.chars.sublist(at), para: l.para);
      lines = [
        (text: l.text.substring(0, at), chars: l.chars.sublist(0, at), para: l.para),
        ...cells,
        if (rest.text.isNotEmpty || !_hasLineAfter(line)) rest,
      ];
      first = line + 1;
    }
    spliceLines(line, line + 1, lines);
    return _respec(first, cells.length, spec);
  }

  /// Inserts an empty row before row [at] (`rows`: after the last).
  TextTable insertRow(TextTable t, int at) {
    final line = t.lineOf(at.clamp(0, t.rows), 0);
    spliceLines(line, line, _cells(t.spec, t.columns));
    return _respec(t.line, t.cells + t.columns, t.spec);
  }

  /// Removes row [row]; the last row removes the table (null then).
  TextTable? removeRow(TextTable t, int row) {
    if (t.rows <= 1) {
      removeTable(t);
      return null;
    }
    final line = t.lineOf(row, 0);
    spliceLines(line, (line + t.columns).clamp(line, t.end), const []);
    return _respec(t.line, t.cells - t.columns, t.spec);
  }

  /// Inserts an empty column before column [at] (`columns`: after the
  /// last), as wide as one of [TableSpec.even]'s; the others narrow to
  /// make room. Nothing at [TableSpec.maxColumns].
  TextTable insertColumn(TextTable t, int at) {
    if (t.columns >= TableSpec.maxColumns) return t;
    final c = at.clamp(0, t.columns);
    final n = t.columns + 1;
    final widths = [for (final w in t.spec.widths) w * t.columns / n]..insert(c, 1 / n);
    final spec = t.spec.copyWith(widths: widths);
    for (var r = t.rows - 1; r >= 0; r--) {
      final line = t.lineOf(r, c);
      spliceLines(line, line, _cells(spec, 1));
    }
    return _respec(t.line, t.rows * n, spec);
  }

  /// Removes column [column]; the last column removes the table (null then).
  TextTable? removeColumn(TextTable t, int column) {
    if (t.columns <= 1) {
      removeTable(t);
      return null;
    }
    _pad(t);
    for (var r = t.rows - 1; r >= 0; r--) {
      final line = t.lineOf(r, column);
      spliceLines(line, line + 1, const []);
    }
    final spec = t.spec.copyWith(widths: [...t.spec.widths]..removeAt(column));
    return _respec(t.line, t.rows * (t.columns - 1), spec);
  }

  /// Gives [t] the shape [spec] (same columns: widths, header).
  TextTable setSpec(TextTable t, TableSpec spec) {
    assert(spec.columns == t.columns);
    return _respec(t.line, t.cells, spec);
  }

  /// Removes the table [t] (a line stays where it was).
  void removeTable(TextTable t) {
    spliceLines(t.line, t.end, const []);
    _ensureLineAfterTables();
  }

  /// Replaces the text of the cell on [line] (its breaks become spaces).
  void setCell(int line, String text, List<SpanStyle> chars) {
    final l = lineAt(line);
    spliceLines(line, line + 1, [(text: text.replaceAll('\n', ' '), chars: chars, para: l.para)]);
  }

  /// Makes the tables consistent after an edit that was not a table edit:
  /// cells' specs and first cells ([TextTables.normalize]), a last row
  /// short of cells filled with empty ones, a line after a table that ends
  /// the text. Whether anything changed.
  bool repairTables() {
    if (!TextTables.any(paras)) return false;
    var changed = false;
    final normal = TextTables.normalize(paras);
    if (!identical(normal, paras) && !_sameParas(normal)) {
      for (var l = 0; l < normal.length; l++) {
        if (para(l) != normal[l]) updateParas(l, l, (_) => normal[l]);
      }
      changed = true;
    }
    for (final t in tables.reversed) {
      if (t.cells % t.columns != 0) {
        _pad(t);
        changed = true;
      }
    }
    return _ensureLineAfterTables() || changed;
  }

  bool _sameParas(List<ParaStyle> other) {
    for (var l = 0; l < other.length; l++) {
      if (para(l) != other[l]) return false;
    }
    return true;
  }

  /// Fills a short last row of [t] with empty cells.
  void _pad(TextTable t) {
    final missing = t.rows * t.columns - t.cells;
    if (missing <= 0) return;
    spliceLines(t.end, t.end, _cells(t.spec, missing));
    _respec(t.line, t.cells + missing, t.spec);
  }

  /// Adds an empty line after a table ending the text, or followed at once
  /// by another table.
  bool _ensureLineAfterTables() {
    final all = tables;
    for (final t in all.reversed) {
      if (!_hasLineAfter(t.end - 1)) {
        spliceLines(t.end, t.end, [_empty(ParaStyle.body)]);
        return _ensureLineAfterTables() || true;
      }
    }
    return false;
  }

  /// Whether a line that is not a table cell follows [line].
  bool _hasLineAfter(int line) => line + 1 < lineCount && !para(line + 1).isCell;

  /// Rewrites the paragraphs of the [cells] lines from [first] as one
  /// table of [spec] (first cell, header row).
  TextTable _respec(int first, int cells, TableSpec spec) {
    for (var k = 0; k < cells; k++) {
      final cell = TableCell(spec, first: k == 0, header: spec.hasHeaderRow && k < spec.columns);
      updateParas(first + k, first + k, (_) => ParaStyle(cell: cell));
    }
    return TextTable(first, cells, spec);
  }

  static List<BufferLine> _cells(TableSpec spec, int n) => [
    for (var k = 0; k < n; k++)
      (text: '', chars: const <SpanStyle>[], para: ParaStyle(cell: TableCell(spec))),
  ];

  static BufferLine _empty(ParaStyle para) =>
      (text: '', chars: const <SpanStyle>[], para: para.isCell ? ParaStyle.body : para);
}
