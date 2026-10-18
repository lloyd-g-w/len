import 'rtf_lines.dart';
import 'text_data.dart';

/// An RTF row definition (`\trowd` up to the row's cells): its cells'
/// right edges (`\cellx`, twips), its left edge (`\trleft`) and whether it
/// is a header row (`\trhdr`).
class RtfRowDef {
  final edges = <int>[];
  int left = 0;
  bool header = false;

  /// A control word of a row definition; false if [name] isn't one.
  bool word(String name, int? param) {
    switch (name) {
      case 'trowd':
        edges.clear();
        left = 0;
        header = false;
      case 'cellx':
        edges.add(param ?? 0);
      case 'trleft':
        left = param ?? 0;
      case 'trhdr':
        header = param != 0;
      default:
        return false;
    }
    return true;
  }

  /// The cells' widths (twips), left to right.
  List<int> get widths => [
    for (var i = 0; i < edges.length; i++) edges[i] - (i == 0 ? left : edges[i - 1]),
  ];
}

/// The rows of an RTF table being read (`\intbl` paragraphs, `\cell`,
/// `\row`), turned into a text box's cell [lines].
class RtfTableRows {
  final _rows = <List<RtfLine>>[];
  final _row = <RtfLine>[];
  RtfLine? _cell;

  /// The first row's cell widths (twips) and header flag.
  List<int>? _widths;
  bool _header = false;

  /// The cell being read.
  RtfLine get cell => _cell ??= RtfLine();

  /// `\cell`: the cell ends.
  void endCell() {
    _row.add(cell);
    _cell = null;
  }

  /// `\row`: the row (of the definition [def]) ends; a cell with text
  /// not yet ended ends with it.
  void endRow(RtfRowDef def) {
    if (!(_cell?.isEmpty ?? true)) endCell();
    _cell = null;
    if (_row.isEmpty) return;
    if (_rows.isEmpty) {
      _widths = def.widths;
      _header = def.header;
    }
    _rows.add([..._row]);
    _row.clear();
  }

  /// A paragraph or nested cell ends inside the cell: a space (one).
  void space() {
    final c = _cell;
    if (c == null || c.isEmpty || c.text.toString().endsWith(' ')) return;
    c.text.write(' ');
    c.styles.add(c.styles.last);
    c.halves.add(c.halves.last);
  }

  /// The table's cell lines (none when it has no cells): the widest row's
  /// columns (at most [TableSpec.maxColumns]; extra cells dropped), short
  /// rows padded; widths from the first row's definition.
  List<RtfLine> lines(RtfRowDef def) {
    endRow(def);
    if (_rows.isEmpty) return const [];
    var columns = 1;
    for (final r in _rows) {
      if (r.length > columns) columns = r.length;
    }
    if (columns > TableSpec.maxColumns) columns = TableSpec.maxColumns;
    final spec = TableSpec(_shares(columns), header: _header);
    final out = <RtfLine>[];
    for (final r in _rows) {
      for (var c = 0; c < columns; c++) {
        out.add(c < r.length ? _trimmed(r[c]) : RtfLine());
      }
    }
    for (final (k, l) in out.indexed) {
      l.cell = ParaStyle(cell: TextTableCell(spec, first: k == 0));
    }
    return out;
  }

  List<double> _shares(int columns) {
    final w = [for (final v in _widths ?? const <int>[]) v.toDouble()];
    if (w.isEmpty) return List.filled(columns, 1);
    final mean = w.fold(0.0, (a, b) => a + b) / w.length;
    return [for (var i = 0; i < columns; i++) i < w.length ? w[i] : mean];
  }

  /// [l] without spaces at its ends.
  static RtfLine _trimmed(RtfLine l) {
    final text = l.text.toString();
    var from = 0, to = text.length;
    while (from < to && text[from] == ' ') {
      from++;
    }
    while (to > from && text[to - 1] == ' ') {
      to--;
    }
    if (from == 0 && to == text.length) return l;
    final out = RtfLine()..text.write(text.substring(from, to));
    out.styles.addAll(l.styles.sublist(from, to));
    out.halves.addAll(l.halves.sublist(from, to));
    return out;
  }
}
