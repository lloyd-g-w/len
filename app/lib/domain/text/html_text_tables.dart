part of 'html_text.dart';

/// Reading tables: the outermost `<table>` becomes an [HtmlTable] whose
/// cells collect their inline content; tables inside its cells are read
/// as the cell's text (their cells and rows separated by spaces).
extension _HtmlTables on _HtmlReader {
  /// Handles the start tag [name] of a table's structure; true when it is
  /// consumed (else it is read as usual, as a cell's element is).
  bool _tableStart(String name, Map<String, String> attrs) {
    final table = _table;
    if (name == 'table') {
      if (table != null) {
        _nested++;
        return false;
      }
      _startTable();
      return true;
    }
    if (table == null || _nested > 0) return false;
    switch (name) {
      case 'thead' || 'tbody' || 'tfoot':
        table.endRow();
        _popTo(_tableBase);
        table.head = name == 'thead';
        return true;
      case 'tr':
        table.startRow();
        _popTo(_tableBase);
        return true;
      case 'td' || 'th':
        _popTo(_tableBase);
        table.startCell(name, attrs);
        _space = false;
        return false;
      case 'col' || 'colgroup':
        if (name == 'col' || attrs.containsKey('width')) table.col(attrs);
        return true;
      case 'caption':
        _stack.add(const ElementFormat(tag: 'caption', hidden: true));
        _hidden++;
        return true;
    }
    return false;
  }

  /// Handles the end tag [name] of a table's structure; true when consumed.
  bool _tableEnd(String name) {
    final table = _table;
    if (table == null) return false;
    if (_nested > 0) {
      if (name == 'table') _nested--;
      return false;
    }
    switch (name) {
      case 'table':
        _endTable();
      case 'td' || 'th':
        _popTo(_tableBase);
        table.cell = null;
      case 'tr':
        table.endRow();
        _popTo(_tableBase);
      case 'thead' || 'tbody' || 'tfoot':
        table.endRow();
        _popTo(_tableBase);
        table.head = false;
      case 'col' || 'colgroup':
        break;
      default:
        return false;
    }
    return true;
  }

  void _startTable() {
    _softBreak();
    _table = HtmlTable();
    _tableBase = _stack.length;
  }

  /// Ends the table being read, its cells becoming lines.
  void _endTable() {
    final table = _table;
    if (table == null) return;
    _popTo(_tableBase);
    _table = null;
    _nested = 0;
    final cells = table.lines();
    if (cells.isEmpty) return;
    // The (empty) line opened before the table is left out unless it
    // parts it from a table before.
    final previous = _lines.length > 1 ? _lines[_lines.length - 2].para : null;
    if (_lines.last.isEmpty && !(previous?.isCell ?? false)) _lines.removeLast();
    _lines
      ..addAll(cells)
      ..add(HtmlLine());
    _space = false;
  }

  /// A block break or `<br>` in a table: a space in a cell.
  void _cellBreak() {
    final line = _line;
    if (_table?.cell == null || line.isEmpty) {
      _space = false;
      return;
    }
    _space = true;
    _spaceStyle = line.chars.last;
  }
}
