part of 'rich_text_controller.dart';

/// The tables of a [RichTextController]'s box: which cell is edited (by a
/// cell's own controller, see `TableCellController`, whose changes come
/// back through [setCell]), a block of cells selected, and the table
/// commands. Every change is a step of the box's history; a cell's typing
/// runs stay one step as in the field.
mixin _RichTextTables on _RichTextState, _RichTextFormatting {
  /// The line of the table cell being edited, if any.
  int? get activeCell {
    final s = _cellSelection;
    return s == null ? null : _buffer.lineOf(s.start);
  }

  /// The selection in the cell being edited, in its own offsets.
  TextSelection? get cellSelection {
    final s = _cellSelection;
    if (s == null) return null;
    final start = _buffer.lineStart(_buffer.lineOf(s.start));
    return TextSelection(baseOffset: s.baseOffset - start, extentOffset: s.extentOffset - start);
  }

  /// The block of cells selected, if any.
  TableRange? get cellRange => _range;

  /// The tables of the box.
  List<TextTable> get tables => _buffer.tables;

  /// The table holding [line], if any.
  TextTable? tableAt(int line) => _buffer.tableAt(line);

  /// The cell on [line] as text of its own (its formatting, the box's
  /// defaults, bold in a header row).
  TextData cellData(int line) => data.cellData(line);

  /// The width the text of the cell on [line] wraps at.
  double cellWrapWidth(int line) {
    final k = tables.indexWhere((t) => t.contains(line));
    if (k < 0 || k >= _plan.tables.length) return double.infinity;
    final t = _plan.tables[k];
    final column = t.table.cellOf(line).column;
    return math.max(1, t.columnWidth(column) - 2 * TableLayout.cellPadX(data));
  }

  /// Starts editing the cell on [line], the caret at [offset] in it (its
  /// end when [atEnd]; its start by default).
  void enterCell(int line, {int? offset, bool atEnd = false}) {
    final start = _buffer.lineStart(line), end = _buffer.lineEnd(line);
    final at = (start + (offset ?? (atEnd ? end - start : 0))).clamp(start, end);
    _range = null;
    _cellSelection = TextSelection.collapsed(offset: at);
    _pending = null;
    final beside = _besideTable(line);
    if (!selection.isValid || _offsets.isHidden(selection.extentOffset)) {
      super.value = value.copyWith(
        selection: TextSelection.collapsed(offset: _offsets.toDisplay(beside)),
      );
    }
    _history.select(_cellSelection!);
    notifyListeners();
  }

  /// The cell's controller moved its selection to [local] (its offsets).
  void selectInCell(TextSelection local, {bool composing = false}) {
    final line = activeCell;
    if (line == null) return;
    final start = _buffer.lineStart(line);
    final next = TextSelection(
      baseOffset: start + local.baseOffset,
      extentOffset: start + local.extentOffset,
    );
    if (next == _cellSelection) return;
    _cellSelection = next;
    _history.select(next, composing: composing);
  }

  /// Leaves the table [t] for the text after it (its first line's start)
  /// or, unless [after], before it (its last line's end); stays in the
  /// table when there is no line there.
  bool leaveTable(TextTable t, {required bool after}) {
    final line = after ? t.end : t.line - 1;
    if (line < 0 || line >= _buffer.lineCount) return false;
    _cellSelection = null;
    _range = null;
    final at = after ? _buffer.lineStart(line) : _buffer.lineEnd(line);
    _sync(TextSelection.collapsed(offset: at));
    notifyListeners();
    return true;
  }

  /// The cell on [line] now holds [cell]'s text and character formats
  /// (what its controller made of it), its selection [local]; [step] says
  /// how it goes into the history (offsets in the cell).
  void setCell(int line, TextData cell, TextSelection local, HistoryStep step) {
    final start = _buffer.lineStart(line);
    _buffer.setCell(line, cell.text, cell.charStyles());
    final length = _buffer.lineEnd(line) - start;
    _cellSelection = TextSelection(
      baseOffset: start + local.baseOffset.clamp(0, length),
      extentOffset: start + local.extentOffset.clamp(0, length),
    );
    _relayout();
    int shift(int v) => v < 0 ? -1 : start + v;
    _history.changed(
      _snapshot,
      runFrom: shift(step.runFrom),
      runTo: shift(step.runTo),
      deletes: step.deletes,
      composing: step.composing,
      command: step.command,
    );
    onDataChanged?.call();
  }

  /// Lays the box out again for the same field text (table rows grown or
  /// shrunk), or anew if the text changed.
  void _relayout() {
    _data = null;
    final breaks = _breaksOf(data);
    final plan = _planOf(data, breaks);
    _breaks = breaks;
    if (plan.offsets.display(_buffer.text) == text) {
      _plan = plan;
      notifyListeners();
    } else {
      final keep = selection.isValid
          ? _modelSelection(selection)
          : const TextSelection.collapsed(offset: 0);
      _sync(
        keep.copyWith(
          baseOffset: keep.baseOffset.clamp(0, _buffer.length),
          extentOffset: keep.extentOffset.clamp(0, _buffer.length),
        ),
      );
      notifyListeners();
    }
  }

  /// A table edit: [edit] changes the buffer and says which cell to edit
  /// after it (its line and offset; null: the field's caret at [caret]).
  void _tableEdit(({int line, int offset})? Function() edit, {int? caret}) {
    final keep = _cellSelection == null ? modelSelection : null;
    final cell = edit();
    _range = null;
    _pending = null;
    var at = (caret ?? keep?.start ?? 0).clamp(0, _buffer.length);
    if (cell != null) {
      final start = _buffer.lineStart(cell.line);
      _cellSelection = TextSelection.collapsed(offset: start + cell.offset);
      at = _besideTable(cell.line);
    } else {
      _cellSelection = null;
    }
    _sync(TextSelection.collapsed(offset: at));
    _history.changed(_snapshot, command: true);
    notifyListeners();
    onDataChanged?.call();
  }

  /// A spot for the field's caret while the cell on [line] is edited: the
  /// start of the line after its table (where the caret may rest).
  int _besideTable(int line) {
    final t = _buffer.tableAt(line);
    if (t == null || t.end >= _buffer.lineCount) return _buffer.length;
    return _buffer.lineStart(t.end);
  }

  /// Inserts a table of [rows] × [columns] at the caret (outside tables)
  /// and edits its first cell.
  void insertTable(int rows, int columns, {bool header = false}) {
    if (activeCell != null) return;
    final at = modelSelection.start;
    _tableEdit(() {
      final r = modelSelection;
      if (!r.isCollapsed) _buffer.replace(r.start, r.end, '', SpanStyle.plain);
      final t = _buffer.insertTable(at, rows, columns, header: header);
      return (line: t.line, offset: 0);
    }, caret: at);
  }

  /// The table, row and column of the cell edited (or the block's anchor).
  ({TextTable table, int row, int column})? get _cellPlace {
    final line = activeCell ?? _rangeAnchorLine;
    if (line == null) return null;
    final t = _buffer.tableAt(line);
    if (t == null) return null;
    final (:row, :column) = t.cellOf(line);
    return (table: t, row: row, column: column);
  }

  int? get _rangeAnchorLine {
    final r = _range;
    if (r == null) return null;
    final t = _buffer.tableAt(r.table);
    return t?.lineOf(r.anchor.row, r.anchor.column);
  }

  /// Whether a cell is edited or cells are selected (table commands apply).
  bool get inTable => _cellPlace != null;

  /// Adds a row above (or [below]) the cell edited, editing its cell in
  /// the same column.
  void insertRow({required bool below}) {
    final p = _cellPlace;
    if (p == null) return;
    final row = below ? p.row + 1 : p.row;
    _tableEdit(() {
      final t = _buffer.insertRow(p.table, row);
      return (line: t.lineOf(row, p.column), offset: 0);
    });
  }

  /// Adds a column left of (or [right] of) the cell edited.
  void insertColumn({required bool right}) {
    final p = _cellPlace;
    if (p == null || p.table.columns >= TableSpec.maxColumns) return;
    final column = right ? p.column + 1 : p.column;
    _tableEdit(() {
      final t = _buffer.insertColumn(p.table, column);
      return (line: t.lineOf(p.row, column), offset: 0);
    });
  }

  /// Removes the row of the cell edited (the rows of the block selected).
  void removeRow() {
    final p = _cellPlace;
    if (p == null) return;
    final r = _range;
    final (top, bottom) = r == null ? (p.row, p.row) : (r.top, r.bottom);
    _tableEdit(() {
      TextTable? t = p.table;
      for (var row = bottom; row >= top && t != null; row--) {
        t = _buffer.removeRow(t, row);
      }
      if (t == null) return null;
      final row = math.min(top, t.rows - 1);
      return (line: t.lineOf(row, math.min(p.column, t.columns - 1)), offset: 0);
    }, caret: _afterTable(p.table));
  }

  /// Removes the column of the cell edited (the columns of the block).
  void removeColumn() {
    final p = _cellPlace;
    if (p == null) return;
    final r = _range;
    final (left, right) = r == null ? (p.column, p.column) : (r.left, r.right);
    _tableEdit(() {
      TextTable? t = p.table;
      for (var c = right; c >= left && t != null; c--) {
        t = _buffer.removeColumn(t, c);
      }
      if (t == null) return null;
      return (line: t.lineOf(p.row, math.min(left, t.columns - 1)), offset: 0);
    }, caret: _afterTable(p.table));
  }

  /// Removes the table of the cell edited; the caret goes where it was.
  void removeTable() {
    final p = _cellPlace;
    if (p == null) return;
    _tableEdit(() {
      _buffer.removeTable(p.table);
      return null;
    }, caret: _afterTable(p.table));
  }

  /// Where the caret goes when the table [t] is removed: the start of the
  /// line that was after it.
  int _afterTable(TextTable t) => _buffer.lineStart(t.line);

  /// Turns the bold header row of the table edited on or off.
  void toggleHeader() {
    final p = _cellPlace;
    if (p == null) return;
    final keep = _cellSelection;
    _tableEdit(() {
      _buffer.setSpec(p.table, p.table.spec.copyWith(header: !p.table.spec.header));
      if (keep == null) return null;
      final line = _buffer.lineOf(keep.start);
      return (line: line, offset: keep.start - _buffer.lineStart(line));
    });
  }

  /// Gives the table starting on [line] column [widths] while a border is
  /// dragged: shown, not yet a step of the history ([commitWidths] ends).
  void previewWidths(int line, List<double> widths) {
    final t = _buffer.tableAt(line);
    if (t == null || widths.length != t.columns) return;
    _buffer.setSpec(t, t.spec.copyWith(widths: widths));
    _relayout();
    onDataChanged?.call();
  }

  /// The widths dragged ([previewWidths]) become one step of the history.
  void commitWidths() => _history.changed(_snapshot, command: true);

  /// Selects the block [range] of cells (no cell edited meanwhile); null
  /// clears it.
  void selectCells(TableRange? range) {
    _range = range;
    if (range != null) _cellSelection = null;
    _pending = null;
    notifyListeners();
  }

  /// Pastes [grid] (rows of cells: their text and character styles) into
  /// the table from the cell on [line] rightwards and down, adding rows
  /// as needed (cells past the last column are dropped); one step.
  void pasteGrid(int line, List<List<({String text, List<SpanStyle> chars})>> grid) {
    var t = _buffer.tableAt(line);
    if (t == null || grid.isEmpty) return;
    final (:row, :column) = t.cellOf(line);
    final table = t.line;
    while (t != null && t.rows < row + grid.length) {
      t = _buffer.insertRow(t, t.rows);
    }
    t = _buffer.tableAt(table);
    if (t == null) return;
    for (var r = 0; r < grid.length; r++) {
      for (var c = 0; c < grid[r].length && column + c < t.columns; c++) {
        final cell = grid[r][c];
        _buffer.setCell(t.lineOf(row + r, column + c), cell.text, cell.chars);
      }
    }
    final last = t.lineOf(
      row + grid.length - 1,
      math.min(t.columns - 1, column + grid.last.length - 1),
    );
    _range = null;
    _cellSelection = TextSelection.collapsed(offset: _buffer.lineEnd(last));
    _relayout();
    _history.changed(_snapshot, command: true);
    notifyListeners();
    onDataChanged?.call();
  }

  /// Empties the cells selected (one step).
  void clearCells() {
    final r = _range;
    final t = r == null ? null : _buffer.tableAt(r.table);
    if (r == null || t == null) return;
    for (final line in r.lines(t).reversed) {
      _buffer.setCell(line, '', const []);
    }
    _relayout();
    _history.changed(_snapshot, command: true);
    notifyListeners();
    onDataChanged?.call();
  }

  /// The cells selected as a box of their own: a table of them (plain
  /// text: rows of tab-separated cells).
  TextData? get rangeData {
    final r = _range;
    final t = r == null ? null : _buffer.tableAt(r.table);
    if (r == null || t == null) return null;
    final widths = [for (var c = r.left; c <= r.right; c++) t.spec.widths[c]];
    final spec = t.spec.copyWith(
      widths: widths,
      continued: false,
      header: t.spec.header && r.top == 0,
    );
    final lines = [
      for (final (k, line) in r.lines(t).indexed)
        (
          text: _buffer.lineAt(line).text,
          chars: _buffer.lineAt(line).chars,
          para: ParaStyle(cell: TextTableCell(spec, first: k == 0)),
        ),
    ];
    final out = RichTextBuffer(const TextData())..spliceLines(0, 1, lines);
    return out.toData(_box);
  }
}
